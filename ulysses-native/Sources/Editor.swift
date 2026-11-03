import AppKit

// MARK: - 编辑器主体（搭视图 + 数据流 + 菜单动作）
// 侧栏的具体实现见 Sidebar.swift，排版引擎见 Styling.swift

final class EditorRoot: NSView, NSTextViewDelegate, NSTextFieldDelegate {
    var titleInput = NSTextField()
    var scrollView = NSScrollView()
    var textView = NSTextView()
    var barLabel = NSTextField()
    var searchField = NSSearchField()
    var plusButton = NSButton()
    var folderButton = NSButton()
    var sidebarScroll = NSScrollView()
    var table = NSOutlineView()
    var toolStack = NSStackView()
    var sidebarWidth: NSLayoutConstraint!
    var titleLeading: NSLayoutConstraint!
    var sidebarViews: [NSView] = []

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

    var baseFont: NSFont { Typo.serif(CGFloat(doc.fontSize)) }
    var bodyParagraph: NSParagraphStyle {
        let p = NSMutableParagraphStyle()
        p.lineSpacing = 10 * CGFloat(doc.fontSize / 17)
        p.paragraphSpacing = 10 * CGFloat(doc.fontSize / 17)
        p.lineBreakMode = .byWordWrapping
        return p
    }
    var bodyAttributes: [NSAttributedString.Key: Any] {
        // 正文色跟随当前主题预设（不是系统语义色），这样切换主题/敲字都不会串色
        let ink = ThemePresets.preset(doc.theme).text
        return [.font: baseFont, .foregroundColor: ink,
                .kern: 0.3, .paragraphStyle: bodyParagraph]
    }
    var bodyAttrList: [NSAttributedString.Key: Any] { bodyAttributes }

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

        folderButton.title = "▤"
        folderButton.bezelStyle = .regularSquare
        folderButton.isBordered = true
        folderButton.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        folderButton.toolTip = "新建分组（也可以右键侧栏）"
        folderButton.target = self
        folderButton.action = #selector(addFolder(_:))
        folderButton.translatesAutoresizingMaskIntoConstraints = false

        table = NSOutlineView()
        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("t"))
        col.resizingMask = .autoresizingMask
        table.addTableColumn(col)
        table.outlineTableColumn = col
        table.headerView = nil
        table.rowHeight = 32
        table.indentationPerLevel = 14
        table.allowsMultipleSelection = false
        table.dataSource = self
        table.delegate = self
        table.backgroundColor = .clear
        table.selectionHighlightStyle = .regular
        table.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        table.setAccessibilityLabel("文稿与分组")
        table.registerForDraggedTypes([NSPasteboard.PasteboardType("com.ulysses.sheet")])
        table.menu = makeSidebarMenu()
        sidebarScroll.documentView = table
        sidebarScroll.hasVerticalScroller = true
        sidebarScroll.drawsBackground = false
        sidebarScroll.translatesAutoresizingMaskIntoConstraints = false

        // --- 编辑器 ---
        titleInput.stringValue = doc.sheet(id: doc.activeId)?.title ?? ""
        titleInput.isBordered = false
        titleInput.drawsBackground = false
        titleInput.placeholderString = "给这篇起个名字"
        titleInput.font = Typo.bold(22)
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
        textView.typingAttributes = bodyAttributes
        textView.defaultParagraphStyle = bodyParagraph
        textView.insertionPointColor = .secondaryLabelColor
        textView.delegate = self
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.textContainerInset = NSSize(width: 40, height: 28)
        textView.textContainer?.widthTracksTextView = true
        scrollView.documentView = textView

        barLabel.font = NSFont.systemFont(ofSize: 11)
        barLabel.textColor = .secondaryLabelColor
        barLabel.isBordered = false
        barLabel.isEditable = false
        barLabel.isSelectable = false
        barLabel.drawsBackground = false
        barLabel.alignment = .left
        barLabel.translatesAutoresizingMaskIntoConstraints = false

        buildToolbar()

        // 侧栏与正文之间的一条细分隔线（约束在主约束块里，避免引用尚未入树的视图）
        let divider = NSBox()
        divider.boxType = .separator
        divider.translatesAutoresizingMaskIntoConstraints = false

        addSubview(searchField)
        addSubview(plusButton)
        addSubview(folderButton)
        addSubview(sidebarScroll)
        addSubview(divider)
        addSubview(titleInput)
        addSubview(toolStack)
        addSubview(scrollView)
        addSubview(barLabel)
        refreshBar()

        // 可插模块（动态派发：对应模块文件不存在时静默跳过，不破坏编译）
        for sel in ["installTheme", "installGoalBar"] as [String] {
            let s = Selector(sel + ":")
            if responds(to: s) { perform(s, with: nil) }
        }

        NSLayoutConstraint.activate([
            divider.leadingAnchor.constraint(equalTo: sidebarScroll.trailingAnchor, constant: 8),
            divider.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            divider.bottomAnchor.constraint(equalTo: barLabel.topAnchor, constant: -6),
            divider.widthAnchor.constraint(equalToConstant: 1),

            searchField.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            searchField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            searchField.widthAnchor.constraint(equalToConstant: 150),
            plusButton.topAnchor.constraint(equalTo: searchField.topAnchor),
            plusButton.leadingAnchor.constraint(equalTo: searchField.trailingAnchor, constant: 4),
            plusButton.widthAnchor.constraint(equalToConstant: 28),
            plusButton.heightAnchor.constraint(equalTo: searchField.heightAnchor),
            folderButton.topAnchor.constraint(equalTo: searchField.topAnchor),
            folderButton.leadingAnchor.constraint(equalTo: plusButton.trailingAnchor, constant: 4),
            folderButton.widthAnchor.constraint(equalToConstant: 28),
            folderButton.heightAnchor.constraint(equalTo: searchField.heightAnchor),
            sidebarScroll.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 8),
            sidebarScroll.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            sidebarScroll.bottomAnchor.constraint(equalTo: barLabel.topAnchor, constant: -6),

            titleInput.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            titleInput.trailingAnchor.constraint(equalTo: toolStack.leadingAnchor, constant: -12),

            toolStack.topAnchor.constraint(equalTo: topAnchor, constant: 14),
            toolStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
            toolStack.heightAnchor.constraint(equalToConstant: 24),

            scrollView.topAnchor.constraint(equalTo: titleInput.bottomAnchor, constant: 6),
            scrollView.leadingAnchor.constraint(equalTo: titleInput.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),

            barLabel.topAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: 6),
            barLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 24),
            barLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -24),
            barLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),
            barLabel.heightAnchor.constraint(equalToConstant: 16),
        ])
        sidebarWidth = sidebarScroll.widthAnchor.constraint(equalToConstant: 236)
        sidebarWidth.isActive = true
        titleLeading = titleInput.leadingAnchor.constraint(equalTo: sidebarScroll.trailingAnchor, constant: 20)
        titleLeading.isActive = true
        sidebarViews = [searchField, plusButton, folderButton, sidebarScroll, divider]
        applySidebarVisibility(animated: false)

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

    // MARK: 顶部工具栏（可见的按钮，不依赖菜单）

    private func buildToolbar() {
        let themeSel = responds(to: Selector(("showThemePanel:"))) ? "showThemePanel:" : "toggleTheme:"
        let specs: [(String, String)] = [
            ("＋ 文稿", "addSheet:"),
            ("▤ 分组", "addFolder:"),
            ("侧栏", "toggleSidebar:"),
            ("导入", "importMDFiles:"),
            ("导出", "exportActiveSheet:"),
            ("打字机", "toggleTypewriter:"),
            ("排版", "toggleMarkdown:"),
            ("外观", themeSel),
            ("目标", "setGoalDialog:"),
            ("指南", "showGuide:"),
        ]
        toolStack = NSStackView()
        toolStack.orientation = .horizontal
        toolStack.spacing = 6
        toolStack.translatesAutoresizingMaskIntoConstraints = false
        for (title, sel) in specs {
            let b = NSButton(title: title, target: self, action: Selector((sel)))
            b.bezelStyle = .texturedRounded
            b.controlSize = .small
            b.font = NSFont.systemFont(ofSize: 11)
            b.isBordered = true
            toolStack.addArrangedSubview(b)
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
        var folder: String? = nil
        if let row = table.selectedRow >= 0 ? table.selectedRow : nil,
           let it = table.item(atRow: row) as? SideItem, let f = it.folder {
            folder = f.id
        }
        let s = Sheet(id: UUID().uuidString, title: t, content: "", folderId: folder)
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
        // 仪表模块接上后刷新进度
        let sel = Selector(("refreshGoalProgress:"))
        if responds(to: sel) { perform(sel, with: nil) }
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

    // MARK: 侧栏收起 / 字号

    @objc func toggleSidebar(_ sender: Any?) {
        doc.sidebarVisible.toggle()
        applySidebarVisibility(animated: true)
        persistNow()
    }

    func applySidebarVisibility(animated: Bool) {
        let show = doc.sidebarVisible
        for v in sidebarViews { v.isHidden = !show }
        sidebarWidth.constant = show ? 236 : 0
        if animated, let w = window {
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.16
                ctx.allowsImplicitAnimation = true
                self.layoutSubtreeIfNeeded()
                w.layoutIfNeeded()
            }, completionHandler: nil)
        } else {
            layoutSubtreeIfNeeded()
        }
    }

    /// 整份文档换掉后刷新视图（导入/迁移/测试用）
    func adoptDoc(_ d: DocState) {
        doc = d
        titleInput.stringValue = doc.sheet(id: doc.activeId)?.title ?? ""
        textView.string = doc.sheet(id: doc.activeId)?.content ?? ""
        applySidebarVisibility(animated: false)
        let themeSel = Selector(("applyTheme:"))
        if responds(to: themeSel) { perform(themeSel, with: nil) }
        reapplyStyles()
        refreshTable()
        refreshBar()
    }

    /// 字号/主题变了之后重排一次（不动 textView，不丢光标）
    func reapplyStyles() {
        Typo.scale = CGFloat(doc.fontSize / 17)
        textView.font = baseFont
        textView.typingAttributes = bodyAttributes
        textView.defaultParagraphStyle = bodyParagraph
        applyMarkdownStyling()
    }
}
