import AppKit

// MARK: - 编辑器主体（搭视图 + 数据流 + 菜单动作）
// 侧栏的具体实现见 Sidebar.swift，排版引擎见 Styling.swift

final class EditorRoot: NSView, NSTextViewDelegate, NSTextFieldDelegate,
                        NSTableViewDataSource, NSTableViewDelegate {
    var titleInput = NSTextField()
    var scrollView = NSScrollView()
    var textView = NSTextView()
    var barLabel = NSTextField()
    var searchField = NSSearchField()
    var plusButton = NSButton()
    var sidebarScroll = NSScrollView()
    var table = NSTableView()

    var saveTimer: Timer? = nil
    var styleTimer: Timer? = nil
    var updatingTable = false

    var doc = Vault.load()

    var activeIndex: Int? { doc.sheets.firstIndex { $0.id == doc.activeId } }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        buildViews()
    }

    required init?(coder: NSCoder) { fatalError("不走 storyboard") }

    let baseFont = NSFont.systemFont(ofSize: 17)

    private func buildViews() {
        wantsLayer = true

        // --- 侧栏 ---
        searchField.placeholderString = "搜索文稿"
        searchField.font = NSFont.systemFont(ofSize: 12)
        searchField.sendsSearchStringImmediately = true
        searchField.target = self
        searchField.action = #selector(searchChanged(_:))
        searchField.translatesAutoresizingMaskIntoConstraints = false

        plusButton.title = "+"
        plusButton.bezelStyle = .regularSquare
        plusButton.isBordered = true
        plusButton.font = NSFont.systemFont(ofSize: 13, weight: .bold)
        plusButton.target = self
        plusButton.action = #selector(addSheet(_:))
        plusButton.translatesAutoresizingMaskIntoConstraints = false

        table = NSTableView()
        table.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier("t")))
        table.headerView = nil
        table.rowHeight = 30
        table.allowsMultipleSelection = false
        table.dataSource = self
        table.delegate = self
        table.setAccessibilityLabel("文稿列表")
        sidebarScroll.documentView = table
        sidebarScroll.hasVerticalScroller = true
        sidebarScroll.drawsBackground = false
        sidebarScroll.translatesAutoresizingMaskIntoConstraints = false

        // --- 编辑器 ---
        titleInput.stringValue = doc.sheet(id: doc.activeId)?.title ?? ""
        titleInput.isBordered = false
        titleInput.drawsBackground = false
        titleInput.placeholderString = "给这篇起个名字"
        titleInput.font = NSFont.boldSystemFont(ofSize: 22)
        titleInput.delegate = self
        titleInput.translatesAutoresizingMaskIntoConstraints = false

        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        textView = NSTextView()
        textView.isRichText = true
        textView.usesFontPanel = false
        textView.string = doc.sheet(id: doc.activeId)?.content ?? ""
        textView.font = baseFont
        textView.delegate = self
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.textContainerInset = NSSize(width: 24, height: 24)
        scrollView.documentView = textView

        barLabel.font = NSFont.systemFont(ofSize: 11)
        barLabel.textColor = .secondaryLabelColor
        barLabel.translatesAutoresizingMaskIntoConstraints = false

        addSubview(searchField)
        addSubview(plusButton)
        addSubview(sidebarScroll)
        addSubview(titleInput)
        addSubview(scrollView)
        addSubview(barLabel)
        refreshBar()

        NSLayoutConstraint.activate([
            searchField.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            searchField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            searchField.widthAnchor.constraint(equalToConstant: 170),
            plusButton.topAnchor.constraint(equalTo: searchField.topAnchor),
            plusButton.leadingAnchor.constraint(equalTo: searchField.trailingAnchor, constant: 4),
            plusButton.widthAnchor.constraint(equalToConstant: 28),
            plusButton.heightAnchor.constraint(equalTo: searchField.heightAnchor),
            sidebarScroll.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 8),
            sidebarScroll.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            sidebarScroll.widthAnchor.constraint(equalToConstant: 212),
            sidebarScroll.bottomAnchor.constraint(equalTo: barLabel.topAnchor, constant: -6),

            titleInput.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            titleInput.leadingAnchor.constraint(equalTo: sidebarScroll.trailingAnchor, constant: 20),
            titleInput.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -24),

            scrollView.topAnchor.constraint(equalTo: titleInput.bottomAnchor, constant: 6),
            scrollView.leadingAnchor.constraint(equalTo: titleInput.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),

            barLabel.topAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: 6),
            barLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 24),
            barLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -24),
            barLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),
        ])

        applyMarkdownStyling()
        refreshTable()

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.window?.makeFirstResponder(self.textView)
            let end = (self.textView.string as NSString).length
            self.textView.setSelectedRange(NSRange(location: end, length: 0))
            if self.doc.typewriter { self.textView.centerSelectionInVisibleArea(nil) }
        }
    }

    // MARK: 切篇 / 新建 / 搜索

    func switchTo(_ id: String) {
        doc.activeId = id
        if let s = doc.sheet(id: id) {
            titleInput.stringValue = s.title
            textView.string = s.content
        }
        applyMarkdownStyling()
        refreshTable()
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.window?.makeFirstResponder(self.textView)
            let end = (self.textView.string as NSString).length
            self.textView.setSelectedRange(NSRange(location: end, length: 0))
            if self.doc.typewriter { self.textView.centerSelectionInVisibleArea(nil) }
        }
        persistNow()
    }

    @objc func addSheet(_ sender: Any?) {
        var n = doc.sheets.count + 1
        var t = "未命名"
        while doc.sheets.contains(where: { $0.title == t }) {
            n += 1
            t = "未命名 \(n)"
        }
        let s = Sheet(id: UUID().uuidString, title: t, content: "")
        doc.sheets.append(s)
        switchTo(s.id)
    }

    @objc func searchChanged(_ sender: Any?) {
        refreshTable()
    }

    // MARK: 保存（800ms 防抖）

    func markDirty() {
        refreshBar()
        restyleSoon()
        saveTimer?.invalidate()
        saveTimer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: false) { [weak self] _ in
            self?.persistNow()
        }
    }

    func persistNow() {
        let ok = Vault.save(doc)
        refreshBar(saved: ok)
    }

    private var activeCount: Int {
        guard let i = activeIndex else { return 0 }
        let c = doc.sheets[i].content
        return statCJK(c) + statLatin(c)
    }

    private func refreshBar(saved: Bool? = nil) {
        let n = activeCount
        let count = n == 0 ? "尚无字数" : "约 \(n) 字"
        var s = "Ulysses Native · \(doc.sheets.count) 篇 · " + count
        if let saved = saved {
            s += " · " + (saved ? "已自动保存" : "保存失败")
        }
        barLabel.stringValue = s
    }

    // MARK: 委托回调

    func controlTextDidChange(_ obj: Notification) {
        switch obj.object as? NSTextField {
        case titleInput:
            if let i = activeIndex {
                doc.sheets[i].title = titleInput.stringValue
                markDirty()
                refreshTable()
            }
        case searchField:
            searchChanged(searchField)
        default:
            break
        }
    }

    func textDidChange(_ notification: Notification) {
        if let i = activeIndex {
            doc.sheets[i].content = textView.string
            markDirty()
            if doc.typewriter {
                DispatchQueue.main.async { [weak self] in
                    self?.textView.centerSelectionInVisibleArea(nil)
                }
            }
        }
    }

    // MARK: 菜单动作（响应链）

    @objc func toggleTypewriter(_ sender: Any?) { doc.typewriter.toggle(); persistNow() }
    @objc func toggleMarkdown(_ sender: Any?) { doc.markdown.toggle(); applyMarkdownStyling(); persistNow() }
    @objc func saveNow(_ sender: Any?) { persistNow() }
}
