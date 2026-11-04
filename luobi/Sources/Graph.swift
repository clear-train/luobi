import AppKit

// MARK: - 人物关系图
//
// 关系不是新填的字段，而是从卡片里已经写好的「关系」那句话里读出来的：
//   A 的关系写着「小明妈妈的学生」→ 画一条 A — 小明妈妈 的线，线上标这句关系。
// 这样你之前填过的资料自动变成一张网，不用再维护第二份数据。

struct GraphEdge: Equatable {
    let from: String
    let to: String
    let label: String
}

struct CardGraph {
    var nodes: [String] = []
    var edges: [GraphEdge] = []
    /// 主角（关系里带"主角"的卡片），画在正中间
    var center: String? = nil
}

extension DocState {
    func cardGraph() -> CardGraph {
        var g = CardGraph()
        let cards = cardSheets
        g.nodes = cards.map { ($0.card?.name.isEmpty == false ? $0.card!.name : $0.title) }
        g.nodes = g.nodes.filter { !$0.isEmpty }

        // 谁的关系里提到了谁
        for c in cards {
            let me = (c.card?.name.isEmpty == false ? c.card!.name : c.title)
            let rel = c.card?.relation ?? ""
            guard !me.isEmpty, !rel.isEmpty else { continue }
            for other in g.nodes where other != me && rel.contains(other) {
                g.edges.append(GraphEdge(from: me, to: other, label: rel))
            }
        }
        g.center = cards.first { ($0.card?.relation ?? "").contains("主角") }
            .map { $0.card?.name.isEmpty == false ? $0.card!.name : $0.title }
        if g.center == nil {
            // 没标主角就选连线最多的人当中心
            var deg: [String: Int] = [:]
            for e in g.edges { deg[e.from, default: 0] += 1; deg[e.to, default: 0] += 1 }
            g.center = g.nodes.max { (deg[$0] ?? 0) < (deg[$1] ?? 0) }
        }
        return g
    }
}

/// 可拖动的关系网视图
final class RelationGraphView: NSView {
    var graph = CardGraph()
    var positions: [String: NSPoint] = [:]
    var onNodeClick: ((String) -> Void)?
    private var dragging: String? = nil
    private var moved = false
    private var dragOffset: NSPoint = .zero

    override var isFlipped: Bool { true }
    private var lastSize = NSSize.zero

    override func layout() {
        super.layout()
        let s = bounds.size
        guard s.width > 20, s.height > 20 else { return }
        if s != lastSize { lastSize = s; layoutNodes(in: s) }
    }

    func layoutNodes(in size: NSSize) {
        positions.removeAll()
        guard !graph.nodes.isEmpty else { return }
        let cx = size.width / 2, cy = size.height / 2
        let others = graph.nodes.filter { $0 != graph.center }
        if let c = graph.center { positions[c] = NSPoint(x: cx, y: cy) }
        let r = min(size.width, size.height) * (others.count > 8 ? 0.40 : 0.34)
        let step = others.isEmpty ? 0 : (2 * Double.pi / Double(others.count))
        for (i, n) in others.enumerated() {
            let a = -Double.pi / 2 + step * Double(i)
            positions[n] = NSPoint(x: cx + CGFloat(cos(a)) * r, y: cy + CGFloat(sin(a)) * r)
        }
    }

    /// 某个坐标落在哪个节点上（测试与点击共用）
    func node(at p: NSPoint) -> String? {
        positions.first { _, q in hypot(p.x - q.x, p.y - q.y) <= 26 }?.key
    }

    func move(_ name: String, to p: NSPoint) {
        positions[name] = p
        needsDisplay = true
    }

    private func nodeRect(_ name: String) -> NSRect {
        guard let p = positions[name] else { return .zero }
        let w: CGFloat = name.count > 4 ? 118 : 92
        return NSRect(x: p.x - w / 2, y: p.y - 15, width: w, height: 30)
    }

    override func draw(_ dirtyRect: NSRect) {
        let preset = ThemePresets.preset("paper")
        preset.bg.setFill()
        bounds.fill()

        // 线先画，节点压在上面
        var labeled: Set<String> = []
        for e in graph.edges {
            guard let a = positions[e.from], let b = positions[e.to] else { continue }
            let dx = b.x - a.x, dy = b.y - a.y
            let dist = max(1, hypot(dx, dy))
            // 略微弯一下，线就不会从中间那个节点里穿过去
            let nx = -dy / dist, ny = dx / dist
            let ctrl = NSPoint(x: (a.x + b.x) / 2 + nx * 22, y: (a.y + b.y) / 2 + ny * 22)
            let path = NSBezierPath()
            path.move(to: a)
            path.curve(to: b, controlPoint1: ctrl, controlPoint2: ctrl)
            path.lineWidth = 1.2
            preset.text.withAlphaComponent(0.28).setStroke()
            path.stroke()

            // 同一句话挂在多个人身上时只标一次；线太短也不标，否则字挤成一团
            guard dist > 150, !labeled.contains(e.from) else { continue }
            labeled.insert(e.from)
            let t: CGFloat = 0.35
            let mt = 1 - t
            let mid = NSPoint(x: mt * mt * a.x + 2 * mt * t * ctrl.x + t * t * b.x,
                              y: mt * mt * a.y + 2 * mt * t * ctrl.y + t * t * b.y)
            let text = e.label.count > 8 ? String(e.label.prefix(8)) + "…" : e.label
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 9.5),
                .foregroundColor: preset.text.withAlphaComponent(0.45),
            ]
            let size = (text as NSString).size(withAttributes: attrs)
            let box = NSRect(x: mid.x - size.width / 2 - 3, y: mid.y - size.height / 2,
                             width: size.width + 6, height: size.height)
            preset.bg.withAlphaComponent(0.9).setFill()
            NSBezierPath(roundedRect: box, xRadius: 3, yRadius: 3).fill()
            (text as NSString).draw(at: NSPoint(x: box.minX + 3, y: box.minY), withAttributes: attrs)
        }

        for n in graph.nodes {
            guard let p = positions[n] else { continue }
            let isCenter = n == graph.center
            let rect = nodeRect(n)
            let path = NSBezierPath(roundedRect: rect, xRadius: isCenter ? 15 : 13, yRadius: isCenter ? 15 : 13)
            (isCenter ? preset.text.withAlphaComponent(0.14) : preset.bg).setFill()
            path.fill()
            preset.text.withAlphaComponent(isCenter ? 0.55 : 0.28).setStroke()
            path.lineWidth = isCenter ? 1.6 : 1
            path.stroke()

            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: isCenter ? 13 : 12, weight: isCenter ? .semibold : .regular),
                .foregroundColor: preset.text,
            ]
            let size = (n as NSString).size(withAttributes: attrs)
            (n as NSString).draw(at: NSPoint(x: p.x - size.width / 2, y: p.y - size.height / 2), withAttributes: attrs)
        }
    }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if let n = node(at: p), let q = positions[n] {
            dragging = n
            moved = false
            dragOffset = NSPoint(x: p.x - q.x, y: p.y - q.y)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let n = dragging else { return }
        let p = convert(event.locationInWindow, from: nil)
        moved = true
        move(n, to: NSPoint(x: p.x - dragOffset.x, y: p.y - dragOffset.y))
    }

    override func mouseUp(with event: NSEvent) {
        if let n = dragging, !moved { onNodeClick?(n) }
        dragging = nil
    }
}

extension EditorRoot {
    @objc func showRelationGraph(_ sender: Any?) {
        let g = doc.cardGraph()
        let preset = ThemePresets.preset(doc.theme)

        let panel = LuobiSheetPanel(contentRect: NSRect(x: 0, y: 0, width: 760, height: 560),
                            styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        panel.title = "人物关系图 · \(g.nodes.count) 人 / \(g.edges.count) 条关系"
        panel.isReleasedWhenClosed = false
        panel.backgroundColor = preset.bg

        let host = NSView(frame: panel.contentView?.bounds ?? .zero)
        host.wantsLayer = true
        host.layer?.backgroundColor = preset.bg.cgColor

        let graphView = RelationGraphView()
        graphView.graph = g
        graphView.translatesAutoresizingMaskIntoConstraints = false
        graphView.onNodeClick = { [weak self, weak panel] name in
            guard let self = self else { return }
            if let s = self.doc.cardSheet(named: name) {
                self.doc.activeId = s.id
                self.refreshTable()
                self.switchTo(s.id)
                if let r = self.row(forID: s.id) {
                    self.table.selectRowIndexes(IndexSet(integer: r), byExtendingSelection: false)
                }
            }
            panel?.close()
        }

        let hint = NSTextField(labelWithString: g.edges.isEmpty
                               ? "还没有连线。在卡片的「关系」里写上别人的名字（如「小明妈妈的学生」），这里就会自动连起来。"
                               : "拖动节点可以重新摆放；点一下人物卡片会打开它的详情。")
        hint.font = NSFont.systemFont(ofSize: 11)
        hint.textColor = preset.text.withAlphaComponent(0.5)
        hint.translatesAutoresizingMaskIntoConstraints = false

        host.addSubview(graphView)
        host.addSubview(hint)
        NSLayoutConstraint.activate([
            graphView.topAnchor.constraint(equalTo: host.topAnchor),
            graphView.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            graphView.trailingAnchor.constraint(equalTo: host.trailingAnchor),
            graphView.bottomAnchor.constraint(equalTo: hint.topAnchor, constant: -6),
            hint.leadingAnchor.constraint(equalTo: host.leadingAnchor, constant: 16),
            hint.trailingAnchor.constraint(lessThanOrEqualTo: host.trailingAnchor, constant: -16),
            hint.bottomAnchor.constraint(equalTo: host.bottomAnchor, constant: -10),
        ])
        let wrap = wrapWithFooter(host)
        wrap.frame = panel.contentLayoutRect
        wrap.autoresizingMask = [.width, .height]
        panel.contentView = wrap
        panel.onEsc = { [weak panel] in panel?.closeSelf() }

        presentSheet(panel)
    }
}
