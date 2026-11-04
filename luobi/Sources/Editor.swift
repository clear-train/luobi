import AppKit

// MARK: - 编辑器主体（搭视图 + 数据流 + 菜单动作）
// 侧栏的具体实现见 Sidebar.swift，排版引擎见 Styling.swift

final class EditorRoot: NSView, NSTextViewDelegate, NSTextFieldDelegate {
    var titleInput = NSTextField()
    var scrollView = NSScrollView()
    var textView = CardTextView()
    var barLabel = NSTextField()
    /// 启动时若自动从备份恢复过，或者刚手动备份过，在这条状态栏里说一句
    var startupNote: String? = Vault.lastRecoveryNote ?? Vault.migrationNote
    var focusMode = false

    // 番茄钟（实现见 Pomodoro.swift）
    var pomoIsBreak = false
    var pomoTimer: Timer?
    var pomoButton: RingButton?
    var pomoRunning = false
    var pomoStartAt: Date?
    var pomoSpent: TimeInterval = 0      // 暂停前累计的秒数
    var pomoNotified = false             // "时间到"只提醒一次
    var goalRing: RingButton?
    /// 外观面板是浮动窗口（不是 sheet）：改配色时你还想点别的、还想看正文
    weak var themePanel: ThemePanelWindow?
    var statusItem: NSStatusItem?
    var statusMenuState: String = ""
    var statusPomoItem: NSMenuItem?
    var statusGoalItem: NSMenuItem?
    var statusTimeItem: NSMenuItem?
    var toastPanel: ToastPanel?
    var toastTimer: Timer?
    var lastActivityAt = Date()
    var sessionTimer: Timer?
    var sessionAccrued = 0
    var lastSavedTotal = 0
    var lastTickTotal = 0
    var readingMode = false
    var readingWasSidebarVisible = true
    var readingMonitor: Any? = nil
    var readingExitButton: NSButton? = nil
    var readingHint: NSTextField? = nil
    var sidebarWasVisible = true
    var focusExitButton = NSButton()
    /// 退出专注的提示淡出计时器；提示只在进来时出现，或鼠标移到顶上时出现
    var focusHintTimer: Timer?
    var focusTopTracker: NSTrackingArea?
    var searchField = NSSearchField()
    var plusButton = NSButton()
    var folderButton = NSButton()
    var sidebarScroll = NSScrollView()
    var table = NSOutlineView()
    var toolStack = NSStackView()
    var sidebarFooter = NSStackView()
    /// 侧栏收起时才出现的「新建」入口（放在主页面右上角）
    var collapsedActions = NSStackView()
    /// 这一段番茄开始时的总字数，用来在结束时告诉你"这一番茄写了多少"
    var pomoStartWords = 0
    var sidebarToggleButton: NSButton? = nil
    var sidebarWidth: NSLayoutConstraint!
    var titleLeading: NSLayoutConstraint!
    /// 正文左边界：平时贴着标题（侧栏让出宽度），专注/阅读时改成贴窗口左边，让正文能真正居中
    var scrollLeading: NSLayoutConstraint!
    var scrollLeadingFull: NSLayoutConstraint!
    var scrollLeadingCompact: NSLayoutConstraint!
    var titleLeadingCompact: NSLayoutConstraint!
    var sidebarViews: [NSView] = []

    // 书库入口：书库 ← → 写作 的切换由外层 Shell 负责，这里只放按钮和书名
    var backButton = NSButton()
    var bookLabel = NSTextField(labelWithString: "")
    var plusMenu: NSPopUpButton?
    var collapseButton = NSButton()
    var expandButton = NSButton()
    var libraryBackHandler: (() -> Void)?
    var tomatoPopover: NSPopover?

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
        p.lineSpacing = CGFloat(doc.lineSpacing) * k
        p.paragraphSpacing = CGFloat(doc.paragraphSpacing) * k
        p.lineBreakMode = .byWordWrapping
        // 中文长篇的习惯：每段首行空两格。标题/引用在排版层会覆盖成 0。
        p.firstLineHeadIndent = CGFloat(doc.indentChars) * CGFloat(doc.fontSize)
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
        backButton.title = "‹ 书库"
        backButton.isBordered = false
        backButton.font = NSFont.systemFont(ofSize: 12)
        backButton.contentTintColor = .secondaryLabelColor
        backButton.alignment = .left
        backButton.target = self
        backButton.action = #selector(backToLibrary(_:))
        backButton.toolTip = "回到书库，换一本书写"
        backButton.translatesAutoresizingMaskIntoConstraints = false

        bookLabel.stringValue = doc.currentBook?.title ?? "未命名"
        bookLabel.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        bookLabel.textColor = .secondaryLabelColor
        bookLabel.lineBreakMode = .byTruncatingTail
        bookLabel.translatesAutoresizingMaskIntoConstraints = false

        collapseButton.title = "«"
        collapseButton.isBordered = false
        collapseButton.font = NSFont.systemFont(ofSize: 13)
        collapseButton.contentTintColor = .secondaryLabelColor
        collapseButton.target = self
        collapseButton.action = #selector(toggleSidebar(_:))
        collapseButton.toolTip = "收起侧栏，专心写正文（再点左边缘的 » 展开）"
        collapseButton.translatesAutoresizingMaskIntoConstraints = false

        expandButton.title = "»"
        expandButton.isBordered = false
        expandButton.font = NSFont.systemFont(ofSize: 13)
        expandButton.contentTintColor = .secondaryLabelColor
        expandButton.target = self
        expandButton.action = #selector(toggleSidebar(_:))
        expandButton.toolTip = "展开左侧文稿树"
        expandButton.isHidden = true
        expandButton.translatesAutoresizingMaskIntoConstraints = false

        searchField.placeholderString = "搜索标题或正文"
        searchField.font = NSFont.systemFont(ofSize: 12)
        searchField.sendsSearchStringImmediately = true
        searchField.target = self
        searchField.action = #selector(searchChanged(_:))
        searchField.translatesAutoresizingMaskIntoConstraints = false

        // 「新建文稿 / 新建分组」原来是两个按钮，占位置还重复；合并成一个下拉
        let plus = NSPopUpButton(frame: .zero, pullsDown: true)
        plus.bezelStyle = .regularSquare
        plus.controlSize = .small
        plus.font = NSFont.systemFont(ofSize: 13, weight: .bold)
        plus.addItem(withTitle: "+")
        func addPlus(_ t: String, _ sel: String) {
            let it = NSMenuItem(title: t, action: Selector(sel), keyEquivalent: "")
            it.target = self
            plus.menu?.addItem(it)
        }
        addPlus("新建文稿", "addSheet:")
        addPlus("新建分组", "addFolder:")
        plus.toolTip = "新建文稿 / 新建分组"
        plus.translatesAutoresizingMaskIntoConstraints = false
        plusMenu = plus

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
        table.target = self
        table.doubleAction = #selector(openSelectedCard(_:))
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
        titleInput.lineBreakMode = .byTruncatingTail
        titleInput.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
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

        textView = CardTextView()
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
        (textView as? CardTextView)?.cardClickHandler = { [weak self] p in
            self?.handleCardClick(at: p) ?? false
        }
        (textView as? CardTextView)?.cardCreateHandler = { [weak self] name in
            self?.handleCreateCard(from: name)
        }
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

        // 侧栏底部常驻入口：新建页面 / 新建章节。
        // 用户反馈"新建页面和新建章节消失了"——顶栏塞不下，但侧栏底部一直有位置。
        sidebarFooter = NSStackView()
        sidebarFooter.orientation = .horizontal
        sidebarFooter.spacing = 6
        sidebarFooter.alignment = .centerY
        sidebarFooter.translatesAutoresizingMaskIntoConstraints = false
        let newPage = CapsuleButton(title: "＋ 页面", action: Selector(("addSheet:")),
                                    tooltip: "新建一篇空白文稿")
        newPage.target = self
        let newChapter = CapsuleButton(title: "＋ 章节", action: Selector(("addChapter:")),
                                       tooltip: "新建一章（自动编号，插在当前这章后面）")
        newChapter.target = self
        sidebarFooter.addArrangedSubview(newPage)
        sidebarFooter.addArrangedSubview(newChapter)
        sidebarFooter.setHuggingPriority(.defaultLow, for: .horizontal)

        // 侧栏与正文之间的一条细分隔线（约束在主约束块里，避免引用尚未入树的视图）
        let divider = NSBox()
        divider.boxType = .separator
        divider.translatesAutoresizingMaskIntoConstraints = false

        addSubview(backButton)
        addSubview(bookLabel)
        addSubview(collapseButton)
        addSubview(expandButton)
        addSubview(searchField)
        addSubview(plus)
        addSubview(sidebarScroll)
        addSubview(sidebarFooter)
        addSubview(divider)
        addSubview(titleInput)
        addSubview(toolStack)
        collapsedActions = NSStackView()
        collapsedActions.orientation = .horizontal
        collapsedActions.spacing = 6
        collapsedActions.alignment = .centerY
        collapsedActions.translatesAutoresizingMaskIntoConstraints = false
        let cPage = CapsuleButton(title: "＋ 页面", action: Selector(("addSheet:")), tooltip: "新建一篇空白文稿")
        cPage.target = self
        let cChapter = CapsuleButton(title: "＋ 章节", action: Selector(("addChapter:")), tooltip: "新建一章")
        cChapter.target = self
        collapsedActions.addArrangedSubview(cPage)
        collapsedActions.addArrangedSubview(cChapter)
        collapsedActions.isHidden = true
        addSubview(collapsedActions)

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
            backButton.topAnchor.constraint(equalTo: topAnchor, constant: 38),
            backButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            backButton.widthAnchor.constraint(equalToConstant: 62),
            backButton.heightAnchor.constraint(equalToConstant: 20),
            bookLabel.centerYAnchor.constraint(equalTo: backButton.centerYAnchor),
            bookLabel.leadingAnchor.constraint(equalTo: backButton.trailingAnchor, constant: 4),
            bookLabel.trailingAnchor.constraint(equalTo: collapseButton.leadingAnchor, constant: -6),
            collapseButton.centerYAnchor.constraint(equalTo: backButton.centerYAnchor),
            collapseButton.trailingAnchor.constraint(equalTo: sidebarScroll.trailingAnchor),
            collapseButton.widthAnchor.constraint(equalToConstant: 22),
            collapseButton.heightAnchor.constraint(equalToConstant: 20),
            searchField.topAnchor.constraint(equalTo: backButton.bottomAnchor, constant: 8),
            searchField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            searchField.trailingAnchor.constraint(equalTo: plus.leadingAnchor, constant: -4),
            plus.centerYAnchor.constraint(equalTo: searchField.centerYAnchor),
            plus.trailingAnchor.constraint(equalTo: leadingAnchor, constant: 228),
            plus.widthAnchor.constraint(equalToConstant: 30),
            plus.heightAnchor.constraint(equalTo: searchField.heightAnchor),
            expandButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            expandButton.topAnchor.constraint(equalTo: topAnchor, constant: 40),
            expandButton.widthAnchor.constraint(equalToConstant: 24),
            expandButton.heightAnchor.constraint(equalToConstant: 22),
            sidebarScroll.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 8),
            sidebarScroll.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            sidebarScroll.bottomAnchor.constraint(equalTo: sidebarFooter.topAnchor, constant: -6),

            sidebarFooter.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            sidebarFooter.trailingAnchor.constraint(equalTo: sidebarScroll.trailingAnchor),
            sidebarFooter.bottomAnchor.constraint(equalTo: barLabel.topAnchor, constant: -6),
            sidebarFooter.heightAnchor.constraint(equalToConstant: 22),

            titleInput.topAnchor.constraint(equalTo: topAnchor, constant: 40),
            titleInput.trailingAnchor.constraint(equalTo: collapsedActions.leadingAnchor, constant: -12),

            toolStack.topAnchor.constraint(equalTo: topAnchor, constant: 42),
            toolStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -18),
            toolStack.heightAnchor.constraint(equalToConstant: 24),
            collapsedActions.trailingAnchor.constraint(equalTo: toolStack.leadingAnchor, constant: -10),
            collapsedActions.centerYAnchor.constraint(equalTo: toolStack.centerYAnchor),
            focusExitButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -18),
            focusExitButton.topAnchor.constraint(equalTo: topAnchor, constant: 42),
            focusExitButton.heightAnchor.constraint(equalToConstant: 24),

            scrollView.topAnchor.constraint(equalTo: titleInput.bottomAnchor, constant: 6),
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
        scrollLeading = scrollView.leadingAnchor.constraint(equalTo: titleInput.leadingAnchor)
        scrollLeadingFull = scrollView.leadingAnchor.constraint(equalTo: leadingAnchor)
        scrollLeadingCompact = scrollView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 32)
        titleLeadingCompact = titleInput.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 32)
        scrollLeading.isActive = true
        sidebarViews = [backButton, bookLabel, collapseButton, searchField, plus, sidebarScroll, sidebarFooter, divider]
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
        // 顶栏只留两个环：新建/分组/收起侧栏都已经挪进侧栏本身了。
        // 剩下的"偶尔用一次"的动作在菜单栏图标和菜单里。
        let groups: [[(String, String, String)]] = [
            [("专注", "toggleFocus:", "藏起所有控件只留正文（Esc 退出）"),
             ("__pomoRing__", "togglePomodoro:", "番茄钟：点一下开始专注，再点暂停；鼠标停在这里看今天的数据"),
             ("__goalRing__", "showTodayPanel:", "今天的进度：点开看今天这一天")],
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
                if sel == "__fileMenu__" {
                    // 导入/导出/成书 是"偶尔用一次"的动作，塞成下拉能省下一条标题的宽度
                    let pop = NSPopUpButton(frame: .zero, pullsDown: true)
                    pop.bezelStyle = .texturedRounded
                    pop.controlSize = .small
                    pop.font = NSFont.systemFont(ofSize: 11)
                    pop.toolTip = "导入、导出本篇、导出整本"
                    pop.addItem(withTitle: "▾ 文件")
                    func add(_ t: String, _ sel: String) {
                        let it = NSMenuItem(title: t, action: Selector(sel), keyEquivalent: "")
                        it.target = self
                        pop.menu?.addItem(it)
                    }
                    add("导入文稿…", "importMDFiles:")
                    add("导出本篇…", "exportActiveSheet:")
                    add("成书：导出整本…", "exportBook:")
                    pop.menu?.addItem(.separator())
                    add("本篇历史版本…", "showHistoryPanel:")
                    pop.menu?.addItem(.separator())
                    add("查找与替换…", "showReplacePanel:")
                    toolStack.addArrangedSubview(pop)
                    continue
                }
                if title == "__pomoRing__" {
                    let ring = RingButton(action: Selector(("togglePomodoro:")), tooltip: tip)
                    ring.target = self
                    ring.glyph = "🍅"
                    ring.glyphFont = 14
                    ring.ringColor = .systemRed
                    ring.onHover = { [weak self] inside in
                        if inside { self?.showTomatoStats() } else { self?.hideTomatoStats() }
                    }
                    pomoButton = ring
                    toolStack.addArrangedSubview(ring)
                    continue
                }
                if title == "__goalRing__" {
                    let ring = RingButton(action: Selector(("showStatsPanel:")), tooltip: tip)
                    ring.target = self
                    ring.glyph = "今"
                    ring.ringColor = .systemBlue
                    goalRing = ring
                    toolStack.addArrangedSubview(ring)
                    continue
                }
                let b = CapsuleButton(title: title, action: Selector((sel)), tooltip: tip)
                b.target = self
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

    /// 新建一章：自动编号，插在当前这章后面（同名就往后顺延）
    @objc func addChapter(_ sender: Any?) {
        var n = doc.sheets.filter { $0.card == nil && $0.title.contains("章") }.count + 1
        var t = "第\(doc.chineseNumber(n))章"
        while doc.sheets.contains(where: { $0.title == t }) {
            n += 1
            t = "第\(doc.chineseNumber(n))章"
        }
        var folder: String? = nil
        if let cur = doc.sheets.first(where: { $0.id == doc.activeId }) {
            folder = cur.folderId
        } else if let row = table.selectedRow >= 0 ? table.selectedRow : nil,
                  let it = table.item(atRow: row) as? SideItem, let f = it.folder {
            folder = f.id
        }
        let s = Sheet(id: UUID().uuidString, title: t, content: "", folderId: folder)
        if let idx = doc.sheets.firstIndex(where: { $0.id == doc.activeId }) {
            doc.sheets.insert(s, at: idx + 1)
        } else {
            doc.sheets.append(s)
        }
        switchTo(s.id)
    }

    @objc func searchChanged(_ sender: Any?) {
        refreshTable()
        let q = searchField.stringValue.trimmingCharacters(in: .whitespaces)
        if q.isEmpty {
            refreshBar()
        } else {
            let n = filtered.count
            barLabel.stringValue = n == 0
                ? "搜索「\(q)」：没有匹配，换个词试试"
                : "搜索「\(q)」：\(n) 篇命中，点一条跳到命中处"
        }
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
        // 先把攒着的写作时长并进去，免得每次落盘丢几秒
        if sessionAccrued > 0 {
            doc.addWriteSeconds(sessionAccrued)
            sessionAccrued = 0
        }
        doc.recordDaily()
        // 按小时记账：只记"新增"的正字数（删字不倒扣，免得把晚上的额度扣掉）
        let nowTotal = doc.sheets.reduce(0) { $0 + statCJK($1.content) + statLatin($1.content) }
        if lastSavedTotal > 0, nowTotal > lastSavedTotal {
            doc.recordHourly(nowTotal - lastSavedTotal)
        }
        lastSavedTotal = nowTotal
        doc.syncCurrentBook()
        let ok = Vault.save(doc)
        // 单篇历史：正文改过才留一份（内部会与最新一份比对，重复就跳过）
        if ok, let cur = doc.sheet(id: doc.activeId) {
            SheetHistory.record(sheet: cur)
        }
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
        var s = "落笔 · \(doc.currentBook?.title ?? "未命名") · \(doc.sheets.count) 篇 · " + count + " · 本书 \(total) 字"
        if doc.dailyGoal > 0 {
            s += " · 今日 \(doc.todayWritten)/\(doc.dailyGoal)"
        }
        if let cur = doc.sheet(id: doc.activeId), cur.target > 0 {
            let st = ChapterStatus.of(words: n, target: cur.target)
            s += " · 本章目标 \(cur.target)（\(st.label)）"
        }
        if let saved = saved {
            s += " · " + (saved ? "已自动保存" : "保存失败：请把 App 拖进「应用程序」后从访达打开")
        }
        if let note = startupNote { s += " · " + note }
        barLabel.stringValue = s
        applyPomodoroVisibility()
        // 仪表模块接上后刷新进度
        let sel = Selector(("refreshGoalProgress:"))
        if responds(to: sel) { perform(sel, with: nil) }

        // 今日进度环：没设目标时用"今天的字数"给个极淡的环，免得永远空着
        let goal = doc.dailyGoal
        if goal > 0 {
            goalRing?.ringProgress = CGFloat(min(1, Double(doc.todayWritten) / Double(goal)))
            goalRing?.ringColor = doc.todayWritten >= goal ? .systemGreen : .systemBlue
            goalRing?.toolTip = "今日 \(doc.todayWritten)/\(goal) 字，点开看统计"
        } else {
            goalRing?.ringProgress = 0
            goalRing?.ringColor = .systemBlue
            goalRing?.toolTip = "还没设今日目标，点开看统计"
        }
        refreshStatusItem()
    }

    // MARK: 委托回调

    func controlTextDidChange(_ obj: Notification) {
        noteActivity()
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
        noteActivity()
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
        doc.indentChars = doc.indentChars == 0 ? 2 : 0
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
    /// 正文栏宽：写字时一眼能扫完一行大概 30–40 个字，所以最宽给到 820pt；
    /// 更宽的窗口把多出来的空间变成两侧留白，而不是把一行拉成一整屏。
    func updateTextInsets() {
        let w = scrollView.bounds.width > 1 ? scrollView.bounds.width : bounds.width
        guard w > 1 else { return }
        if focusMode || readingMode {
            let column = min(CGFloat(720), max(CGFloat(420), w - 160))
            textView.textContainerInset = NSSize(width: max(40, (w - column) / 2), height: 40)
        } else {
            let column = min(w - 80, CGFloat(820))
            textView.textContainerInset = NSSize(width: max(40, (w - column) / 2), height: 28)
        }
    }

    /// 三种横向状态：侧栏展开 / 侧栏收起 / 专注·阅读（铺满）。
    /// 以前正文左边界绕了一圈挂在标题上，侧栏一收窄标题的约束就打架，
    /// 结果正文只扩张一点点、左边留一条空带。现在三种状态各用一条独立约束。
    func updateHorizontalLayout() {
        let full = focusMode || readingMode
        let compact = doc.sidebarVisible && !full
        titleLeading.isActive = compact
        titleLeadingCompact.isActive = !compact
        scrollLeading.isActive = compact
        scrollLeadingFull.isActive = !compact
        _ = full
        updateTextInsets()
    }

    override func layout() {
        super.layout()
        updateTextInsets()
    }

    func applyFocusMode() {
        let on = focusMode
        updateTextInsets()
        toolStack.isHidden = on
        collapsedActions.isHidden = on || doc.sidebarVisible
        refreshGoalProgress(nil)
        if on {
            // 进来时给一次提示，2.4 秒后自己淡掉；之后把鼠标移到顶边才会再出现
            showFocusHint(autoHide: true)
        } else {
            focusHintTimer?.invalidate()
            focusHintTimer = nil
            focusExitButton.isHidden = true
            focusExitButton.alphaValue = 1
        }
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

    // MARK: 专注模式的「退出提示」

    func showFocusHint(autoHide: Bool) {
        guard focusMode else { return }
        focusHintTimer?.invalidate()
        focusHintTimer = nil
        focusExitButton.isHidden = false
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.18
            self.focusExitButton.animator().alphaValue = 1
        }, completionHandler: nil)
        guard autoHide else { return }
        let t = Timer(timeInterval: 2.4, repeats: false) { [weak self] _ in
            self?.hideFocusHint()
        }
        RunLoop.main.add(t, forMode: .common)
        focusHintTimer = t
    }

    func hideFocusHint() {
        guard focusMode else { return }
        focusHintTimer?.invalidate()
        focusHintTimer = nil
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.35
            self.focusExitButton.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            guard let self = self, self.focusMode else { return }
            self.focusExitButton.isHidden = true
            self.focusExitButton.alphaValue = 1
        })
    }

    /// 顶部 64pt 是"悬停区"：鼠标移到这里才提示怎么退出
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let old = focusTopTracker { removeTrackingArea(old) }
        let rect = NSRect(x: 0, y: max(0, bounds.height - 64), width: bounds.width, height: 64)
        let area = NSTrackingArea(rect: rect,
                                  options: [.mouseEnteredAndExited, .activeInKeyWindow],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        focusTopTracker = area
    }

    override func mouseEntered(with event: NSEvent) {
        if focusMode { showFocusHint(autoHide: false) }
        super.mouseEntered(with: event)
    }

    override func mouseExited(with event: NSEvent) {
        if focusMode { hideFocusHint() }
        super.mouseExited(with: event)
    }

    override func cancelOperation(_ sender: Any?) {
        if readingMode {
            toggleReading(nil)
            return
        }
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
        updateHorizontalLayout()
        for v in sidebarViews { v.isHidden = !show }
        sidebarWidth.constant = show ? 236 : 0
        expandButton.isHidden = show || focusMode || readingMode
        // 收起来以后，新建入口挪到主页面右上
        collapsedActions.isHidden = show || focusMode || readingMode

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
        bookLabel.stringValue = doc.currentBook?.title ?? "未命名"
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

extension EditorRoot {

    @objc func backToLibrary(_ sender: Any?) {
        flushSession()
        persistNow()
        libraryBackHandler?()
    }

    /// 鼠标停在番茄环上：今天写了多少、几个番茄、专注多久，一屏看完。
    /// 用浮层而不是状态栏，是因为"想知道"的时机是鼠标停下来的那一瞬间。
    /// 番茄浮层要显示的全部文案（抽出来是为了能被测试直接检查）
    func tomatoStatsText() -> String {
        let minutes = doc.todaySeconds / 60
        var lines: [String] = []
        var head = "今天 \(doc.todayWritten) 字"
        if doc.dailyGoal > 0 { head += " / 目标 \(doc.dailyGoal)" }
        lines.append(head)
        if doc.dailyGoal > 0 {
            let pct = min(999, Int(Double(doc.todayWritten) / Double(doc.dailyGoal) * 100))
            lines.append("目标完成 \(pct)% · 还差 \(max(0, doc.dailyGoal - doc.todayWritten)) 字")
        }
        if doc.showSpeed {
            if doc.todaySeconds > 30 && doc.todayWritten > 0 {
                let rate = Double(doc.todayWritten) * 60 / Double(max(1, doc.todaySeconds))
                let rateText = rate < 10 ? String(format: "%.1f", rate) : String(format: "%.0f", rate)
                var speed = "速度 · 平均 \(rateText) 字/分钟"
                if doc.peakWPM > 0 { speed += " · 最快 \(doc.peakWPM) 字/分钟" }
                lines.append(speed)
                lines.append("时间 · 专注 \(minutes) 分钟")
            } else if doc.todaySeconds > 30 {
                lines.append("时间 · 专注 \(minutes) 分钟（今天还没净增字）")
            } else {
                lines.append("速度 · 今天还没开始计时")
            }
        }
        if doc.showEffect {
            let p = doc.todayPomodoros
            if p > 0 {
                lines.append("效率 · 每个番茄 \(doc.todayWritten / p) 字 · 共 \(p) 个")
            } else {
                lines.append("效率 · 完整做完一个番茄才有「每番茄字数」")
            }
            let week = doc.writeStats(days: 7)
            if week.activeDays > 0 {
                let avg = week.totalWords / max(1, week.activeDays)
                if avg > 0 {
                    let diff = doc.todayWritten - avg
                    let pct = Int(abs(Double(diff) / Double(avg) * 100))
                    lines.append("对比 · 近 7 天平均 \(avg) 字/天，今天\(diff >= 0 ? "高" : "低") \(pct)%")
                }
            }
        }
        if doc.shadowMode {
            let sh = doc.shadow()
            if sh.hasHistory {
                lines.append("影子 · 过去的你这会儿 \(sh.expected) 字，你现在 \(sh.actual) 字（\(sh.verdict)）")
            } else {
                lines.append("影子：再写几天就有参照了")
            }
        }
        if hasPomoSession {
            if pomoIsBreak {
                lines.append(pomoRunning ? "休息中 · 还剩 \(pomoRemainingText)" : "休息已暂停")
            } else if pomoIsOvertime {
                lines.append("已超时 +\(pomoOvertimeText)（还在写）")
            } else if pomoRunning {
                lines.append("专注中 · 还剩 \(pomoRemainingText)")
            } else {
                lines.append("专注已暂停 · 还剩 \(pomoRemainingText)")
            }
        } else if doc.pomodoroEnabled {
            lines.append("点一下开始 \(doc.focusMinutes) 分钟专注")
        }
        return lines.joined(separator: "\n")
    }

    func showTomatoStats() {
        guard let btn = pomoButton else { return }
        let pop = tomatoPopover ?? NSPopover()
        pop.behavior = .semitransient
        pop.animates = false
        let label = NSTextField(labelWithString: tomatoStatsText())
        label.font = NSFont.systemFont(ofSize: 12)
        label.textColor = .labelColor
        label.maximumNumberOfLines = 0
        label.preferredMaxLayoutWidth = 220
        let box = NSView(frame: NSRect(x: 0, y: 0, width: 240, height: 0))
        label.translatesAutoresizingMaskIntoConstraints = false
        box.addSubview(label)
        // 浮层底部留一个「设置…」，不想看这些数字的人从这里关
        let link = NSButton(title: "设置…（可以关掉这些）", target: self,
                            action: Selector(("showSettingsPanel:")))
        link.isBordered = false
        link.font = NSFont.systemFont(ofSize: 11)
        link.contentTintColor = .secondaryLabelColor
        link.translatesAutoresizingMaskIntoConstraints = false
        box.addSubview(link)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 14),
            label.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -14),
            label.topAnchor.constraint(equalTo: box.topAnchor, constant: 10),
            link.leadingAnchor.constraint(equalTo: label.leadingAnchor, constant: -2),
            link.topAnchor.constraint(equalTo: label.bottomAnchor, constant: 4),
            link.bottomAnchor.constraint(equalTo: box.bottomAnchor, constant: -6),
        ])
        let vc = NSViewController()
        vc.view = box
        pop.contentViewController = vc
        pop.contentSize = box.fittingSize
        pop.show(relativeTo: btn.bounds, of: btn, preferredEdge: .minY)
        tomatoPopover = pop
    }

    func hideTomatoStats() {
        tomatoPopover?.close()
        tomatoPopover = nil
    }
}
