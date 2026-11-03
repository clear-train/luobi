import AppKit

// MARK: - 编辑器主体（搭视图 + 数据流 + 菜单动作）
// 侧栏的具体实现见 Sidebar.swift，排版引擎见 Styling.swift

final class EditorRoot: NSView, NSTextViewDelegate, NSTextFieldDelegate {
    var titleInput = NSTextField()
    var scrollView = NSScrollView()
    var textView = NSTextView()
    var barLabel = NSTextField()
    /// 启动时若自动从备份恢复过，或者刚手动备份过，在这条状态栏里说一句
    var startupNote: String? = Vault.lastRecoveryNote
    var focusMode = false
    var sidebarWasVisible = true
    var focusExitButton = NSButton()
    var searchField = NSSearchField()
    var plusButton = NSButton()
    var folderButton = NSButton()
    var sidebarScroll = NSScrollView()
    var table = NSOutlineView()
    var toolStack = NSStackView()
    var sidebarFooter = NSStackView()
    var sidebarToggleButton: NSButton? = nil
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
        let k = CGFloat(doc.fontSize / 17)
        p.lineSpacing = 10 * k
        p.paragraphSpacing = 10 * k
        p.lineBreakMode = .byWordWrapping
        // 中文长篇的习惯：每段首行空两格。标题/引用在排版层会覆盖成 0。
        p.firstLineHeadIndent = doc.indentParagraphs ? CGFloat(doc.fontSize) * 2 : 0
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
        table.rowHeight = 28
        table.indentationPerLevel = 12
        if #available(macOS 11.0, *) { table.style = .sourceList }
        table.selectionHighlightStyle = .sourceList
        table.setDraggingSourceOperationMask(.move, forLocal: true)
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
        textView.isHorizontallyResizable = false
        // 手动装配 scrollView 时必须自己声明：窗口变宽/侧栏收起时正文跟着变宽
        textView.autoresizingMask = [.width]
        textView.textContainerInset = NSSize(width: 40, height: 28)
        updateTextInsets()
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

        // 侧栏底部常驻入口：不靠记快捷键，也不靠翻菜单
        let footHint = NSTextField(labelWithString: "右键管理 · 拖动归档")
        footHint.font = NSFont.systemFont(ofSize: 10.5)
        footHint.textColor = .tertiaryLabelColor
        footHint.translatesAutoresizingMaskIntoConstraints = false
        sidebarFooter = NSStackView()
        sidebarFooter.orientation = .horizontal
        sidebarFooter.spacing = 6
        sidebarFooter.alignment = .centerY
        sidebarFooter.translatesAutoresizingMaskIntoConstraints = false
        let footGoal = NSButton(title: "写作目标", target: self, action: Selector(("setGoalDialog:")))
        footGoal.bezelStyle = .texturedRounded
        footGoal.controlSize = .small
        footGoal.font = NSFont.systemFont(ofSize: 10.5)
        footGoal.toolTip = "设定本篇的目标字数，底部会出现进度条"
        let footGuide = NSButton(title: "功能说明", target: self, action: Selector(("showGuide:")))
        footGuide.bezelStyle = .texturedRounded
        footGuide.controlSize = .small
        footGuide.font = NSFont.systemFont(ofSize: 10.5)
        footGuide.toolTip = "打开使用指南（也能在「帮助」菜单里找到）"
        sidebarFooter.addArrangedSubview(footHint)
        sidebarFooter.addArrangedSubview(footGoal)
        sidebarFooter.addArrangedSubview(footGuide)
        sidebarFooter.setHuggingPriority(.defaultLow, for: .horizontal)

        // 侧栏与正文之间的一条细分隔线（约束在主约束块里，避免引用尚未入树的视图）
        let divider = NSBox()
        divider.boxType = .separator
        divider.translatesAutoresizingMaskIntoConstraints = false

        addSubview(searchField)
        addSubview(plusButton)
        addSubview(folderButton)
        addSubview(sidebarScroll)
        addSubview(sidebarFooter)
        addSubview(divider)
        addSubview(titleInput)
        addSubview(toolStack)

        focusExitButton = NSButton(title: "退出专注（Esc）", target: self, action: Selector(("toggleFocus:")))
        focusExitButton.bezelStyle = .texturedRounded
        focusExitButton.controlSize = .small
        focusExitButton.font = NSFont.systemFont(ofSize: 11)
        focusExitButton.toolTip = "回到完整界面：侧栏、工具栏都回来"
        focusExitButton.isHidden = true
        focusExitButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(focusExitButton)
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
            divider.topAnchor.constraint(equalTo: topAnchor, constant: 40),
            divider.bottomAnchor.constraint(equalTo: barLabel.topAnchor, constant: -6),
            divider.widthAnchor.constraint(equalToConstant: 1),

            // 顶部留出 40pt 给窗口交通灯（标题栏已隐藏，内容铺满整窗）
            searchField.topAnchor.constraint(equalTo: topAnchor, constant: 40),
            searchField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            searchField.widthAnchor.constraint(equalToConstant: 148),
            plusButton.topAnchor.constraint(equalTo: searchField.topAnchor),
            plusButton.leadingAnchor.constraint(equalTo: searchField.trailingAnchor, constant: 4),
            plusButton.widthAnchor.constraint(equalToConstant: 28),
            plusButton.heightAnchor.constraint(equalTo: searchField.heightAnchor),
            folderButton.topAnchor.constraint(equalTo: searchField.topAnchor),
            folderButton.leadingAnchor.constraint(equalTo: plusButton.trailingAnchor, constant: 4),
            folderButton.widthAnchor.constraint(equalToConstant: 28),
            folderButton.heightAnchor.constraint(equalTo: searchField.heightAnchor),
            sidebarScroll.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 8),
            sidebarScroll.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            sidebarScroll.bottomAnchor.constraint(equalTo: sidebarFooter.topAnchor, constant: -6),

            sidebarFooter.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            sidebarFooter.trailingAnchor.constraint(equalTo: sidebarScroll.trailingAnchor),
            sidebarFooter.bottomAnchor.constraint(equalTo: barLabel.topAnchor, constant: -6),
            sidebarFooter.heightAnchor.constraint(equalToConstant: 22),

            titleInput.topAnchor.constraint(equalTo: topAnchor, constant: 40),
            titleInput.trailingAnchor.constraint(equalTo: toolStack.leadingAnchor, constant: -12),

            toolStack.topAnchor.constraint(equalTo: topAnchor, constant: 42),
            toolStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -18),
            toolStack.heightAnchor.constraint(equalToConstant: 24),
            focusExitButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -18),
            focusExitButton.topAnchor.constraint(equalTo: topAnchor, constant: 42),
            focusExitButton.heightAnchor.constraint(equalToConstant: 24),

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
        sidebarViews = [searchField, plusButton, folderButton, sidebarScroll, sidebarFooter, divider]
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
        // 分组排布：文稿 → 文件 → 写作 → 外观/帮助，中间用细线隔开，
        // 每个按钮都带 tooltip，不需要背快捷键。
        let groups: [[(String, String, String)]] = [
            [("＋ 新建文稿", "addSheet:", "新建一篇文稿"),
             ("▤ 新建分组", "addFolder:", "新建一个分组（文件夹），文稿可以拖进去")],
            [("导入", "importMDFiles:", "从磁盘导入 Markdown 文件"),
             ("导出", "exportActiveSheet:", "把当前这篇导出为 Markdown"),
             ("成书", "exportBook:", "把分组里的稿子按侧栏顺序拼成整本（网页或 Markdown）")],
            [("侧栏", "toggleSidebar:", "收起或展开左侧文稿树"),
             ("打字机", "toggleTypewriter:", "光标所在行始终停在屏幕中间，眼睛不用上下找"),
             ("排版", "toggleMarkdown:", "按 Markdown 语法实时排版标题、加粗与引用"),
             ("缩进", "toggleIndent:", "每段首行缩进两字（中文长篇的版面习惯）"),
             ("专注", "toggleFocus:", "收起侧栏与工具栏，只留正文（Esc 退出）")],
            [("外观", themeSel, "切换纸色、深浅与正文字号")],
            [("指南", "showGuide:", "功能说明与使用指南")],
        ]
        toolStack = NSStackView()
        toolStack.orientation = .horizontal
        toolStack.spacing = 5
        toolStack.setHuggingPriority(.required, for: .horizontal)
        toolStack.translatesAutoresizingMaskIntoConstraints = false
        for (gi, group) in groups.enumerated() {
            if gi > 0 {
                let sep = NSBox()
                sep.boxType = .separator
                sep.translatesAutoresizingMaskIntoConstraints = false
                sep.widthAnchor.constraint(equalToConstant: 1).isActive = true
                sep.heightAnchor.constraint(equalToConstant: 16).isActive = true
                toolStack.addArrangedSubview(sep)
            }
            for (title, sel, tip) in group {
                let b = NSButton(title: title, target: self, action: Selector((sel)))
                b.bezelStyle = .texturedRounded
                b.controlSize = .small
                b.font = NSFont.systemFont(ofSize: 11)
                b.isBordered = true
                b.toolTip = tip
                if sel == "toggleSidebar:" { sidebarToggleButton = b }
                toolStack.addArrangedSubview(b)
            }
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

    func refreshBar(saved: Bool? = nil) {
        let n = activeCount
        let total = doc.sheets.reduce(0) { $0 + statCJK($1.content) + statLatin($1.content) }
        let count = n == 0 ? "本篇空白" : "本篇 \(n) 字"
        var s = "Ulysses Native · \(doc.sheets.count) 篇 · " + count + " · 全书 \(total) 字"
        if let saved = saved {
            s += " · " + (saved ? "已自动保存" : "保存失败：请把 App 拖进「应用程序」后从访达打开")
        }
        if let note = startupNote { s += " · " + note }
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

    @objc func toggleIndent(_ sender: Any?) {
        doc.indentParagraphs.toggle()
        applyMarkdownStyling()
        textView.typingAttributes = bodyAttributes
        persistNow()
    }

    // MARK: 专注模式：只留正文，其他全部让位

    @objc func toggleFocus(_ sender: Any?) {
        focusMode.toggle()
        applyFocusMode()
    }

    /// 专注模式把正文收成一条居中的阅读栏（约 720pt 宽），避免字跑到屏幕两端
    private func updateTextInsets() {
        let w = bounds.width
        if focusMode && w > 0 {
            let column = min(CGFloat(720), max(CGFloat(420), w - 160))
            textView.textContainerInset = NSSize(width: max(40, (w - column) / 2), height: 40)
        } else {
            textView.textContainerInset = NSSize(width: 40, height: 28)
        }
    }

    override func layout() {
        super.layout()
        if focusMode { updateTextInsets() }
    }

    func applyFocusMode() {
        let on = focusMode
        updateTextInsets()
        toolStack.isHidden = on
        focusExitButton.isHidden = !on
        titleInput.isHidden = on
        if on {
            // 进专注时顺手记住侧栏原本的状态，退出时还原
            sidebarWasVisible = doc.sidebarVisible
            doc.sidebarVisible = false
        } else {
            doc.sidebarVisible = sidebarWasVisible
        }
        applySidebarVisibility(animated: true)
    }

    override func cancelOperation(_ sender: Any?) {
        if focusMode {
            toggleFocus(nil)
            return
        }
        super.cancelOperation(sender)
    }
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
        sidebarToggleButton?.title = show ? "收起侧栏" : "展开侧栏"
        sidebarToggleButton?.toolTip = show ? "把左侧文稿树收起来，专心写正文" : "重新展开左侧文稿树"
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
