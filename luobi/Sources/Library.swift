import AppKit

// MARK: - 书库：进来先挑一本书，而不是直接掉进正文里

func fmtWords(_ n: Int) -> String {
    if n >= 10000 { return String(format: "%.1f 万字", Double(n) / 10000) }
    return "\(n) 字"
}

func fmtAgo(_ ts: Double) -> String {
    guard ts > 0 else { return "还没动过" }
    let d = Date().timeIntervalSince1970 - ts
    if d < 60 { return "刚刚" }
    if d < 3600 { return "\(Int(d / 60)) 分钟前" }
    if d < 86400 { return "\(Int(d / 3600)) 小时前" }
    return "\(Int(d / 86400)) 天前"
}

/// 一本书的卡片。鼠标移上去才展开细节——平时保持安静，需要时给数字。
final class BookCardView: NSView {
    let book: Book
    var onOpen: (() -> Void)?
    var onQuickNote: (() -> Void)?

    private let titleLabel = NSTextField(labelWithString: "")
    private let metaLabel = NSTextField(labelWithString: "")
    private let detailLabel = NSTextField(labelWithString: "")
    private var hovered = false
    private var tracking: NSTrackingArea?

    init(book: Book) {
        self.book = book
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.borderWidth = 1
        translatesAutoresizingMaskIntoConstraints = true

        titleLabel.stringValue = book.title
        titleLabel.font = Typo.bold(book.isEssays ? 19 : 17)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        metaLabel.font = NSFont.systemFont(ofSize: 11.5)
        metaLabel.textColor = .secondaryLabelColor
        metaLabel.lineBreakMode = .byTruncatingTail
        metaLabel.translatesAutoresizingMaskIntoConstraints = false

        detailLabel.font = NSFont.systemFont(ofSize: 11)
        detailLabel.textColor = .secondaryLabelColor
        detailLabel.alphaValue = 0
        detailLabel.maximumNumberOfLines = 2
        detailLabel.translatesAutoresizingMaskIntoConstraints = false

        if book.isEssays {
            metaLabel.stringValue = "\(book.sheets.count) 篇速记 · 随手写，不用想放哪"
            detailLabel.stringValue = "点开接着写，或点右下角「＋ 速记」"
        } else {
            let cards = book.cardCount
            metaLabel.stringValue = "\(book.chapterCount) 章 · \(fmtWords(book.words))"
            var d = "最近改动 \(fmtAgo(book.updatedAt))"
            if cards > 0 { d += " · 人物卡 \(cards) 张" }
            detailLabel.stringValue = d
        }

        addSubview(titleLabel)
        addSubview(metaLabel)
        addSubview(detailLabel)
        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 16),
            metaLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            metaLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
            metaLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 6),
            detailLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            detailLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
            detailLabel.topAnchor.constraint(equalTo: metaLabel.bottomAnchor, constant: 10),
        ])

        if book.isEssays {
            let quick = CapsuleButton(title: "＋ 速记", action: #selector(quickTapped(_:)), tooltip: "新建一条未归档的速记，直接落在随笔夹里")
            quick.target = self
            quick.translatesAutoresizingMaskIntoConstraints = false
            addSubview(quick)
            NSLayoutConstraint.activate([
                quick.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
                quick.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12),
                quick.heightAnchor.constraint(equalToConstant: 22),
            ])
        }
        applyLook()
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    @objc private func quickTapped(_ sender: Any?) { onQuickNote?() }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = tracking { removeTrackingArea(t) }
        let t = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                               owner: self, userInfo: nil)
        addTrackingArea(t)
        tracking = t
    }

    override func mouseEntered(with event: NSEvent) {
        hovered = true
        applyLook()
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.12
            detailLabel.animator().alphaValue = 1
        })
    }

    override func mouseExited(with event: NSEvent) {
        hovered = false
        applyLook()
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.18
            detailLabel.animator().alphaValue = 0
        })
    }

    override func mouseDown(with event: NSEvent) {
        onOpen?()
    }

    private func applyLook() {
        let preset = ThemePresets.preset(book.isEssays ? "paper" : "paper")
        let base = preset.bg.blended(withFraction: book.isEssays ? 0.10 : 0.04, of: .black) ?? preset.bg
        layer?.backgroundColor = (hovered ? base.blended(withFraction: 0.04, of: .white) ?? base : base).cgColor
        layer?.borderColor = (hovered ? NSColor.tertiaryLabelColor : NSColor.separatorColor).cgColor
    }
}

/// 卡片墙：手动流式布局，列数跟着窗口宽度走
final class LibraryGrid: NSView {
    var cards: [BookCardView] = [] { didSet { cards.forEach(addSubview); needsLayout = true } }

    override var isFlipped: Bool { true }

    private let cardW: CGFloat = 236
    private let cardH: CGFloat = 150
    private let gap: CGFloat = 16
    private let padX: CGFloat = 28
    private let padTop: CGFloat = 12

    override func layout() {
        super.layout()
        guard !cards.isEmpty else { return }
        let usable = bounds.width - padX * 2
        let cols = max(1, Int((usable + gap) / (cardW + gap)))
        for (i, c) in cards.enumerated() {
            let r = i / cols, col = i % cols
            c.frame = NSRect(x: padX + CGFloat(col) * (cardW + gap),
                             y: padTop + CGFloat(r) * (cardH + gap),
                             width: cardW, height: cardH)
        }
    }

    func contentHeight() -> CGFloat {
        guard !cards.isEmpty else { return 0 }
        let usable = bounds.width - padX * 2
        let cols = max(1, Int((usable + gap) / (cardW + gap)))
        let rows = Int(ceil(Double(cards.count) / Double(cols)))
        return padTop + CGFloat(rows) * (cardH + gap) + 12
    }
}

final class LibraryView: NSView {
    var doc: DocState
    var onOpenBook: ((String) -> Void)?
    var onNewBook: (() -> Void)?
    var onQuickNote: (() -> Void)?
    var onDeleteBook: ((String) -> Void)?
    var onRenameBook: ((String) -> Void)?

    private let titleLabel = NSTextField(labelWithString: "落笔")
    private let subLabel = NSTextField(labelWithString: "")
    private let newButton = CapsuleButton(title: "＋ 新建书", action: Selector(("newBookPressed:")), tooltip: "建一本新书，从空白开始")
    private let scroll = NSScrollView()
    private let grid = LibraryGrid()

    init(doc: DocState) {
        self.doc = doc
        super.init(frame: .zero)
        wantsLayer = true
        build()
        reload()
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { false }

    private func build() {
        titleLabel.font = Typo.bold(28)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        subLabel.font = NSFont.systemFont(ofSize: 12.5)
        subLabel.textColor = .secondaryLabelColor
        subLabel.translatesAutoresizingMaskIntoConstraints = false
        newButton.target = self
        newButton.translatesAutoresizingMaskIntoConstraints = false

        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.documentView = grid
        grid.translatesAutoresizingMaskIntoConstraints = false

        addSubview(titleLabel)
        addSubview(subLabel)
        addSubview(newButton)
        addSubview(scroll)

        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 28),
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 40),
            subLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            subLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 6),
            newButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -28),
            newButton.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            newButton.heightAnchor.constraint(equalToConstant: 26),
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            scroll.topAnchor.constraint(equalTo: subLabel.bottomAnchor, constant: 18),
            scroll.bottomAnchor.constraint(equalTo: bottomAnchor),
            grid.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
            grid.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
            grid.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
        ])
    }

    @objc private func newBookPressed(_ sender: Any?) { onNewBook?() }

    func reload(doc newDoc: DocState? = nil) {
        if let d = newDoc { doc = d }
        let preset = ThemePresets.preset(doc.theme)
        layer?.backgroundColor = preset.bg.cgColor
        titleLabel.textColor = preset.text
        subLabel.textColor = preset.text.withAlphaComponent(0.55)

        let books = doc.books.filter { !$0.isEssays }.sorted {
            // 最近改的排前面；同一秒建的多本书按书名定序，避免顺序忽上忽下
            $0.updatedAt == $1.updatedAt ? $0.title < $1.title : $0.updatedAt > $1.updatedAt
        }
        let essays = doc.books.first { $0.isEssays }
        var cards: [BookCardView] = []
        for b in books {
            let c = BookCardView(book: b)
            c.onOpen = { [weak self] in self?.onOpenBook?(b.id) }
            cards.append(c)
        }
        if let e = essays {
            let c = BookCardView(book: e)
            c.onOpen = { [weak self] in self?.onOpenBook?(e.id) }
            c.onQuickNote = { [weak self] in self?.onQuickNote?() }
            cards.append(c)
        }
        grid.cards = cards

        let today = doc.todayWritten
        var sub = "\(books.count) 本书"
        if let e = essays { sub += " · 随笔夹 \(e.sheets.count) 篇" }
        sub += " · 今天写了 \(today) 字"
        subLabel.stringValue = sub

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.grid.frame = NSRect(x: 0, y: 0, width: self.scroll.contentView.bounds.width,
                                     height: max(self.scroll.contentView.bounds.height, self.grid.contentHeight()))
            self.grid.needsLayout = true
        }
    }

    override func layout() {
        super.layout()
        grid.frame = NSRect(x: 0, y: 0, width: scroll.contentView.bounds.width,
                            height: max(scroll.contentView.bounds.height, grid.contentHeight()))
        grid.needsLayout = true
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu()
        let pointInGrid = grid.convert(event.locationInWindow, from: nil)
        for c in grid.cards where c.frame.contains(pointInGrid) {
            let rename = NSMenuItem(title: "重命名「\(c.book.title)」…", action: #selector(renameTapped(_:)), keyEquivalent: "")
            rename.target = self
            rename.representedObject = c.book.id
            menu.addItem(rename)
            if c.book.isEssays {
                let note = NSMenuItem(title: "新建一条速记", action: #selector(noteTapped(_:)), keyEquivalent: "")
                note.target = self
                menu.addItem(note)
            } else {
                let del = NSMenuItem(title: "删除这本书…", action: #selector(deleteTapped(_:)), keyEquivalent: "")
                del.target = self
                del.representedObject = c.book.id
                menu.addItem(.separator())
                menu.addItem(del)
            }
            return menu
        }
        let nb = NSMenuItem(title: "新建书", action: #selector(newBookPressed(_:)), keyEquivalent: "")
        nb.target = self
        menu.addItem(nb)
        return menu
    }

    @objc private func renameTapped(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        onRenameBook?(id)
    }

    @objc private func deleteTapped(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        onDeleteBook?(id)
    }

    @objc private func noteTapped(_ sender: Any?) { onQuickNote?() }
}
