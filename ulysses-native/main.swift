import Foundation
import AppKit

// MARK: - 数据模型：从「一篇」长成「多篇」

struct Sheet: Codable {
    var id: String
    var title: String
    var content: String
    var updatedAt: Double = 0 // 以后侧栏按时间排序用，先占位
}

struct DocState: Codable {
    var sheets: [Sheet]
    var activeId: String
    var typewriter: Bool = true
    var markdown: Bool = true

    static func initial() -> DocState {
        let s = Sheet(id: UUID().uuidString, title: "第一章", content: "开始写。")
        return DocState(sheets: [s], activeId: s.id)
    }

    func sheet(id: String) -> Sheet? { sheets.first { $0.id == id } }
}

// 旧版单篇文档的形状，只迁移用
struct LegacyDoc: Codable {
    var title: String?
    var content: String?
    var typewriter: Bool?
    var markdown: Bool?
}

enum Vault {
    static var dir: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("UlyssesNative", isDirectory: true)
    }
    static var file: URL { dir.appendingPathComponent("state.json") }

    static func ensure() {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    static func load() -> DocState {
        ensure()
        guard let data = try? Data(contentsOf: file), !data.isEmpty else { return .initial() }
        if let fresh = try? JSONDecoder().decode(DocState.self, from: data),
           !fresh.sheets.isEmpty, fresh.sheet(id: fresh.activeId) != nil {
            return fresh
        }
        // 迁移：老 state.json（单篇）→ 新结构（多篇），内容一点不丢
        if let legacy = try? JSONDecoder().decode(LegacyDoc.self, from: data) {
            let s = Sheet(id: UUID().uuidString,
                          title: legacy.title ?? "未命名",
                          content: legacy.content ?? "")
            return DocState(sheets: [s], activeId: s.id,
                            typewriter: legacy.typewriter ?? true,
                            markdown: legacy.markdown ?? true)
        }
        return .initial()
    }

    static func save(_ doc: DocState) -> Bool {
        ensure()
        do {
            let tmp = file.appendingPathExtension("tmp")
            try JSONEncoder().encode(doc).write(to: tmp, options: .atomic)
            try? FileManager.default.removeItem(at: file)
            try FileManager.default.moveItem(at: tmp, to: file)
            return true
        } catch {
            return false
        }
    }
}

// MARK: - 统计

func statCJK(_ s: String) -> Int {
    s.unicodeScalars.filter { u in
        (0x2E80...0x9FFF).contains(u.value)
            || (0x3400...0x4DBF).contains(u.value)
            || (0xF900...0xFAFF).contains(u.value)
            || (0x3040...0x30FF).contains(u.value)
    }.count
}

func statLatin(_ s: String) -> Int {
    var n = 0
    var inWord = false
    for u in s.unicodeScalars {
        let isLetter = u.value < 0x80 && (u.properties.isAlphabetic || u.properties.numericType != nil)
        if isLetter {
            if !inWord { n += 1; inWord = true }
        } else {
            inWord = false
        }
    }
    return n
}

// MARK: - 界面：侧栏 + 编辑器

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
    private var updatingTable = false

    private(set) var doc = Vault.load()

    private var activeIndex: Int? { doc.sheets.firstIndex { $0.id == doc.activeId } }

    private var filtered: [Sheet] {
        let q = searchField.stringValue.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return doc.sheets }
        return doc.sheets.filter {
            $0.title.lowercased().contains(q) || $0.content.lowercased().contains(q)
        }
    }

    // 底座样式和档位表
    private let baseFont = NSFont.systemFont(ofSize: 17)
    private let headingFonts: [NSFont] = [
        NSFont.boldSystemFont(ofSize: 26),
        NSFont.boldSystemFont(ofSize: 23),
        NSFont.boldSystemFont(ofSize: 20),
        NSFont.boldSystemFont(ofSize: 18),
        NSFont.boldSystemFont(ofSize: 17),
        NSFont.boldSystemFont(ofSize: 16),
    ]

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        buildViews()
    }

    required init?(coder: NSCoder) { fatalError("不走 storyboard") }

    // MARK: 搭视图

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
            // 侧栏列
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

            // 编辑列
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

        // 选中当前篇、光标进正文
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.window?.makeFirstResponder(self.textView)
            let end = (textView.string as NSString).length
            textView.setSelectedRange(NSRange(location: end, length: 0))
            if doc.typewriter { textView.centerSelectionInVisibleArea(nil) }
            }
    }

    // MARK: 侧栏数据源

    func numberOfRows(in tableView: NSTableView) -> Int { filtered.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let cellID = NSUserInterfaceItemIdentifier("cell")
        let tf = (tableView.makeView(withIdentifier: cellID, owner: nil) as? NSTextField)
            ?? {
                let f = NSTextField(labelWithString: "")
                f.identifier = cellID
                f.font = NSFont.systemFont(ofSize: 13)
                f.lineBreakMode = .byTruncatingTail
                return f
            }()
        let s = filtered[row]
        tf.stringValue = s.title.isEmpty ? "未命名" : s.title
        tf.textColor = s.id == doc.activeId ? .labelColor : .secondaryLabelColor
        return tf
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard !updatingTable else { return }
        let row = table.selectedRow
        guard row >= 0, row < filtered.count else { return }
        let id = filtered[row].id
        guard id != doc.activeId else { return }
        switchTo(id)
    }

    private func refreshTable() {
        updatingTable = true
        table.reloadData()
        if let row = filtered.firstIndex(where: { $0.id == doc.activeId }) {
            table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            table.scrollRowToVisible(row)
        }
        updatingTable = false
    }

    // MARK: 切篇 / 新建 / 搜索

    private func switchTo(_ id: String) {
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
            let end = (textView.string as NSString).length
            textView.setSelectedRange(NSRange(location: end, length: 0))
            if doc.typewriter { textView.centerSelectionInVisibleArea(nil) }
        }
        persistNow()
    }

    @objc func addSheet(_ sender: Any?) {
        var n = doc.sheets.count + 1
        var t = "未命名"
        // 避免重名堆叠：未命名2、未命名3…
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

    // MARK: 排版

    private func restyleSoon() {
        styleTimer?.invalidate()
        styleTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: false) { [weak self] _ in
            self?.applyMarkdownStyling()
        }
    }

    private func applyMarkdownStyling() {
        let storage = textView.textStorage!
        let full = NSRange(location: 0, length: storage.length)
        guard doc.markdown else {
            storage.setAttributes([.font: baseFont], range: full)
            return
        }
        storage.setAttributes([
            .font: baseFont,
            .foregroundColor: NSColor.labelColor,
        ], range: full)

        let ns = storage.string as NSString
        if full.length == 0 { return }
        ns.enumerateSubstrings(in: full, options: [.byLines]) { [weak self] line, _, enclosing, _ in
            guard let self = self, let line = line else { return }
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { return }

            let hashCount = trimmed.prefix { $0 == "#" }.count
            if hashCount >= 1 && hashCount <= 6 {
                let rest = trimmed.dropFirst(hashCount)
                if rest.isEmpty || rest.hasPrefix(" ") || rest.hasPrefix("\t") {
                    let para = NSMutableParagraphStyle()
                    para.paragraphSpacing = 8
                    storage.addAttributes([
                        .font: self.headingFonts[hashCount - 1],
                        .paragraphStyle: para,
                    ], range: enclosing)
                    return
                }
            }

            var searchStart = line.startIndex
            while let first = line.range(of: "**", range: searchStart..<line.endIndex) {
                if let close = line.range(of: "**", range: first.upperBound..<line.endIndex) {
                    let inner = first.upperBound..<close.lowerBound
                    let r = NSRange(inner, in: line)
                    let shifted = NSRange(location: enclosing.location + r.location, length: r.length)
                    if shifted.length > 0 {
                        storage.addAttributes([.font: NSFont.boldSystemFont(ofSize: 17)], range: shifted)
                    }
                    searchStart = close.upperBound
                } else {
                    break
                }
            }

            if trimmed.hasPrefix(">") {
                storage.addAttributes([
                    .font: NSFontManager.shared.convert(self.baseFont, toHaveTrait: [.italicFontMask]),
                    .foregroundColor: NSColor.secondaryLabelColor,
                ], range: enclosing)
            }
        }
    }

    // MARK: 保存（800ms 防抖）

    private func markDirty() {
        refreshBar()
        restyleSoon()
        saveTimer?.invalidate()
        saveTimer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: false) { [weak self] _ in
            self?.persistNow()
        }
    }

    private func persistNow() {
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

    // MARK: 委托回调：写入当前篇

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

    // MARK: 菜单动作

    @objc func toggleTypewriter(_ sender: Any?) { doc.typewriter.toggle(); persistNow() }
    @objc func toggleMarkdown(_ sender: Any?) { doc.markdown.toggle(); applyMarkdownStyling(); persistNow() }
    @objc func saveNow(_ sender: Any?) { persistNow() }
}

// MARK: - 组装窗口与菜单

let app = NSApplication.shared

let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1080, height: 680),
                   styleMask: [.titled, .closable, .miniaturizable, .resizable],
                   backing: .buffered, defer: false)
win.title = "Ulysses Native"
win.minSize = NSSize(width: 780, height: 460)
win.contentView = EditorRoot()
win.center()
win.setFrameAutosaveName("UlyssesNativeMain")
win.makeKeyAndOrderFront(nil)

let main = NSMenu()
for (name, items) in [
    ("应用", [
        NSMenuItem(title: "退出 Ulysses Native", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"),
    ]),
    ("文件", [
        NSMenuItem(title: "新建文稿", action: Selector(("addSheet:")), keyEquivalent: "n"),
        NSMenuItem(title: "立即保存", action: Selector(("saveNow:")), keyEquivalent: "s"),
    ]),
    ("编辑", [
        NSMenuItem(title: "撤销", action: Selector(("undo:")), keyEquivalent: "z"),
        NSMenuItem(title: "重做", action: Selector(("redo:")), keyEquivalent: "Z"),
        { let s = NSMenuItem.separator(); return s }(),
        NSMenuItem(title: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x"),
        NSMenuItem(title: "拷贝", action: #selector(NSText.copy(_:)), keyEquivalent: "c"),
        NSMenuItem(title: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v"),
        NSMenuItem(title: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"),
    ]),
    ("视图", [
        {
            let i = NSMenuItem(title: "打字机居中", action: Selector(("toggleTypewriter:")), keyEquivalent: "t")
            i.keyEquivalentModifierMask = [.command, .option]
            return i
        }(),
        {
            let i = NSMenuItem(title: "Markdown 排版", action: Selector(("toggleMarkdown:")), keyEquivalent: "m")
            i.keyEquivalentModifierMask = [.command, .option]
            return i
        }(),
    ]),
    ("窗口", [
        NSMenuItem(title: "最小化", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m"),
        NSMenuItem(title: "关闭", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"),
    ]),
] as [(String, [NSMenuItem])] {
    let root = NSMenuItem()
    main.addItem(root)
    let m = NSMenu(title: name)
    root.submenu = m
    items.forEach(m.addItem)
}
main.autoenablesItems = false
app.mainMenu = main

app.setActivationPolicy(.regular)
app.run()
