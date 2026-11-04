import AppKit

// MARK: - 大纲板
//
// 侧栏的树能看"有哪些"，看不出"整本长什么样"。
// 这里把章节平铺成一堵卡片墙：标题 + 字数 + 开头两句，扫一眼就有全景。
// 拖动卡片可以重排（跨分组也行），点一下进入那一章。

/// 一章相对目标的处境。写作时最常问自己"这段够不够"，这里给个客观参照
enum ChapterStatus {
    case none      // 没设目标
    case short     // 不到目标的 80%
    case ok        // 80%–120%
    case long      // 超过 120%

    var label: String {
        switch self {
        case .none: return ""
        case .short: return "偏短"
        case .ok: return "刚好"
        case .long: return "偏长"
        }
    }

    static func of(words: Int, target: Int) -> ChapterStatus {
        guard target > 0 else { return .none }
        if words < Int(Double(target) * 0.8) { return .short }
        if words > Int(Double(target) * 1.2) { return .long }
        return .ok
    }
}

struct BoardItem {
    let sheet: Sheet
    let words: Int
    let preview: String
    let folderName: String?
    var status: ChapterStatus { ChapterStatus.of(words: words, target: sheet.target) }
}

extension DocState {
    /// 大纲板的卡片顺序 = 阅读顺序（树的顺序，跳过人物卡）
    func boardItems() -> [BoardItem] {
        var out: [BoardItem] = []
        func walk(_ parent: String?) {
            for f in childFolders(of: parent) {
                walk(f.id)
            }
            for s in sheets(in: parent) where s.card == nil {
                let lines = s.content
                    .split(separator: "\n", omittingEmptySubsequences: true)
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
                let preview = lines.prefix(2).joined(separator: " / ")
                out.append(BoardItem(sheet: s,
                                     words: statCJK(s.content) + statLatin(s.content),
                                     preview: preview,
                                     folderName: parent.flatMap { folder(id: $0)?.name }))
            }
        }
        walk(nil)
        return out
    }
}

final class BoardView: NSView {
    var items: [BoardItem] = []
    var onOpen: ((String) -> Void)?
    var onMove: ((Int, Int) -> Void)?

    private var rects: [NSRect] = []
    private var dragFrom: Int? = nil
    private var dragPoint: NSPoint = .zero
    private var dropTo: Int? = nil
    private var moved = false
    private let pad: CGFloat = 16
    private let gap: CGFloat = 14
    private let cardH: CGFloat = 118

    override var isFlipped: Bool { true }

    /// 按可用宽度排成网格，返回总高度
    @discardableResult
    func layoutCards(width: CGFloat) -> CGFloat {
        rects.removeAll()
        guard width > 0 else { return 0 }
        let minW: CGFloat = 200
        let cols = max(1, Int((width - pad * 2 + gap) / (minW + gap)))
        let cardW = (width - pad * 2 - gap * CGFloat(cols - 1)) / CGFloat(cols)
        for (i, _) in items.enumerated() {
            let r = i / cols, c = i % cols
            rects.append(NSRect(x: pad + CGFloat(c) * (cardW + gap),
                                y: pad + CGFloat(r) * (cardH + gap),
                                width: cardW, height: cardH))
        }
        let rows = (items.count + cols - 1) / cols
        return pad * 2 + CGFloat(max(0, rows)) * cardH + CGFloat(max(0, rows - 1)) * gap
    }

    func cardRects() -> [NSRect] { rects }

    func index(at p: NSPoint) -> Int? {
        rects.firstIndex { $0.contains(p) }
    }

    private func preset() -> ThemePreset { ThemePresets.preset("paper") }

    override func draw(_ dirtyRect: NSRect) {
        let p = preset()
        p.bg.setFill()
        bounds.fill()

        for (i, item) in items.enumerated() where i < rects.count {
            var r = rects[i]
            let dragging = dragFrom == i && moved
            if dragging {
                r.origin.x += dragPoint.x
                r.origin.y += dragPoint.y
            }
            let path = NSBezierPath(roundedRect: r, xRadius: 10, yRadius: 10)
            p.bg.setFill()
            path.fill()
            p.text.withAlphaComponent(dragging ? 0.5 : 0.18).setStroke()
            path.lineWidth = 1
            path.stroke()

            // 标题
            let title = item.sheet.title.isEmpty ? "未命名" : item.sheet.title
            let ta: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
                .foregroundColor: p.text,
            ]
            (title as NSString).draw(in: NSRect(x: r.minX + 12, y: r.minY + 10,
                                               width: r.width - 24, height: 34), withAttributes: ta)

            // 分组 + 字数
            let meta = [item.folderName, "\(item.words) 字"].compactMap { $0 }.joined(separator: " · ")
            let ma: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 10),
                .foregroundColor: p.text.withAlphaComponent(0.45),
            ]
            (meta as NSString).draw(at: NSPoint(x: r.minX + 12, y: r.minY + 46), withAttributes: ma)

            // 目标与状态（右上角）
            if item.sheet.target > 0 {
                let st = item.status
                let color: NSColor = st == .ok ? NSColor.systemGreen : (st == .short ? NSColor.systemOrange : NSColor.systemRed)
                let badge = "目标 \(item.sheet.target) · \(st.label)"
                let ba: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: 10, weight: .medium),
                    .foregroundColor: color.withAlphaComponent(st == .ok ? 0.85 : 0.9),
                ]
                let size = (badge as NSString).size(withAttributes: ba)
                (badge as NSString).draw(at: NSPoint(x: r.maxX - 12 - size.width, y: r.minY + 46), withAttributes: ba)
            }

            // 开头两句
            let pa: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 11),
                .foregroundColor: p.text.withAlphaComponent(0.62),
            ]
            (item.preview as NSString).draw(in: NSRect(x: r.minX + 12, y: r.minY + 64,
                                                       width: r.width - 24, height: 44), withAttributes: pa)
        }

        // 拖拽落点的一条竖线
        if let to = dropTo, to <= rects.count {
            let x: CGFloat
            if to < rects.count { x = rects[to].minX - gap / 2 } else { x = (rects.last?.maxX ?? pad) + gap / 2 }
            let line = NSRect(x: x, y: pad, width: 2, height: max(1, (rects.last?.maxY ?? pad) - pad))
            p.text.withAlphaComponent(0.5).setFill()
            line.fill()
        }

        if items.isEmpty {
            let msg = "还没有正文。新建一篇，它就会出现在这里。"
            let a: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 12),
                                                    .foregroundColor: p.text.withAlphaComponent(0.4)]
            (msg as NSString).draw(at: NSPoint(x: pad, y: pad), withAttributes: a)
        }
    }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        dragFrom = index(at: p)
        dragPoint = .zero
        moved = false
        dropTo = nil
    }

    override func mouseDragged(with event: NSEvent) {
        guard let from = dragFrom else { return }
        let p = convert(event.locationInWindow, from: nil)
        guard let r = rects[safe: from] else { return }
        let cx = p.x - (r.midX), cy = p.y - (r.midY)
        if abs(cx) > 4 || abs(cy) > 4 { moved = true }
        dragPoint = NSPoint(x: cx, y: cy)
        // 落点：拖到哪张卡的前半段就插在它前面
        dropTo = index(at: p)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        defer { dragFrom = nil; dragPoint = .zero; dropTo = nil; moved = false; needsDisplay = true }
        guard let from = dragFrom else { return }
        if moved {
            if let to = dropTo, to != from { onMove?(from, to) }
        } else {
            if let i = index(at: convert(event.locationInWindow, from: nil)) { onOpen?(items[i].sheet.id) }
            else if let i = dragFrom { _ = i }
        }
    }
}

private extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}

extension EditorRoot {
    @objc func showBoard(_ sender: Any?) {
        let preset = ThemePresets.preset(doc.theme)
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 860, height: 620),
                            styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        panel.title = "大纲板"
        if ThemePresets.preset(doc.theme).isDark { panel.appearance = NSAppearance(named: .darkAqua) }
        panel.isReleasedWhenClosed = false
        panel.backgroundColor = preset.bg

        let host = NSView()
        host.wantsLayer = true
        host.layer?.backgroundColor = preset.bg.cgColor

        let header = NSTextField(labelWithString: "")
        header.font = NSFont.systemFont(ofSize: 12)
        header.textColor = preset.text.withAlphaComponent(0.55)
        header.translatesAutoresizingMaskIntoConstraints = false

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = true
        scroll.backgroundColor = preset.bg
        scroll.translatesAutoresizingMaskIntoConstraints = false

        let board = BoardView()
        board.translatesAutoresizingMaskIntoConstraints = false
        scroll.documentView = board

        func reload() {
            let items = doc.boardItems()
            board.items = items
            let w = max(400, scroll.contentView.bounds.width)
            let h = board.layoutCards(width: w)
            board.frame = NSRect(x: 0, y: 0, width: w, height: max(h, scroll.contentView.bounds.height))
            board.needsDisplay = true
            let total = items.reduce(0) { $0 + $1.words }
            let off = items.filter { $0.status == .short || $0.status == .long }.count
            let withTarget = items.filter { $0.sheet.target > 0 }.count
            let goalNote = withTarget == 0 ? "" : (off == 0 ? " · 全部在目标区间" : " · \(off) 章偏离目标")
            header.stringValue = "共 \(items.count) 章 · 约 \(total) 字\(goalNote)　（拖动卡片可重排，点一下进入那一篇）"
        }

        board.onOpen = { [weak self, weak panel] id in
            guard let self = self else { return }
            self.switchTo(id)
            if let r = self.row(forID: id) { self.table.selectRowIndexes(IndexSet(integer: r), byExtendingSelection: false) }
            panel?.close()
        }
        board.onMove = { [weak self] from, to in
            guard let self = self else { return }
            if self.moveBoardItem(from: from, to: to) { reload() }
        }

        host.addSubview(header)
        host.addSubview(scroll)
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: host.topAnchor, constant: 12),
            header.leadingAnchor.constraint(equalTo: host.leadingAnchor, constant: 16),
            scroll.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 8),
            scroll.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: host.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: host.bottomAnchor),
        ])
        panel.contentView = host

        if let win = window { win.beginSheet(panel) { _ in } } else { panel.makeKeyAndOrderFront(nil) }

        // 面板真正拿到尺寸后再排版（否则宽度是 0）
        DispatchQueue.main.async {
            host.layoutSubtreeIfNeeded()
            reload()
        }
    }

    /// 把第 from 张卡挪到第 to 张的位置；跨分组时改归属
    @discardableResult
    func moveBoardItem(from: Int, to: Int) -> Bool {
        var order = doc.boardItems().map { $0.sheet }
        guard from >= 0, from < order.count, to >= 0, to <= order.count, from != to else { return false }
        let moving = order.remove(at: from)
        var insertAt = to > from ? to - 1 : to
        insertAt = min(max(0, insertAt), order.count)
        let targetFolder: String?
        if insertAt < order.count { targetFolder = order[insertAt].folderId }
        else if let last = order.last { targetFolder = last.folderId }
        else { targetFolder = nil }
        guard let idx = doc.sheets.firstIndex(where: { $0.id == moving.id }) else { return false }
        doc.sheets[idx].folderId = targetFolder
        let anchor = insertAt < order.count ? order[insertAt].id : nil
        reorder(moving.id, toFolder: targetFolder, before: anchor)
        persistNow()
        return true
    }
}

extension EditorRoot {

    /// 给当前这一篇（或右键点中的那一篇）设目标字数
    @objc func setChapterTarget(_ sender: Any?) {
        guard let sheet = contextSideItem()?.sheet ?? doc.sheet(id: doc.activeId) else { return }
        let alert = NSAlert()
        alert.messageText = "「\(sheet.title.isEmpty ? "未命名" : sheet.title)」的目标字数"
        alert.informativeText = "填 0 表示不设目标。\n设了以后：状态栏显示本章进度，大纲板上标「偏短 / 刚好 / 偏长」（以 ±20% 为界）。"
        alert.addButton(withTitle: "保存")
        alert.addButton(withTitle: "取消")

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        field.stringValue = "\(sheet.target)"
        field.alignment = .right
        alert.accessoryView = field
        alert.window.initialFirstResponder = field

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let v = max(0, min(500_000, Int(field.stringValue.trimmingCharacters(in: .whitespaces)) ?? sheet.target))
        if let i = doc.sheets.firstIndex(where: { $0.id == sheet.id }) {
            doc.sheets[i].target = v
        }
        persistNow()
        refreshBar()
        startupNote = v == 0 ? "已取消本章目标" : "本章目标：\(v) 字"
        refreshBar()
    }
}
