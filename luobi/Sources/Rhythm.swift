import AppKit

// MARK: - 写作节奏（按"一天里的第几个小时"看效率）
//
// 统计面板回答"最近写了多少"，这个面板回答"我什么时候写得动"：
//   · 一天里哪个整点产量最高/最低
//   · 最快手速多少字/分钟（来自每 20 秒一次的采样）
//   · 峰值之后在哪个小时掉到一半以下 —— 这就是你的拐点，该收工了

final class RhythmChartView: NSView {
    var stats: RhythmStats?
    var accent: NSColor = .systemOrange

    override var isFlipped: Bool { true }

    /// 24 根柱子的位置（供绘制与测试共用）
    func barRects(in rect: NSRect = .zero) -> [(hour: Int, rect: NSRect, avg: Int)] {
        let area = rect == .zero ? bounds : rect
        guard let s = stats else { return [] }
        let maxAvg = max(1, s.averages.max() ?? 1)
        let labelHeight: CGFloat = 16
        let plot = NSRect(x: area.minX + 4, y: area.minY + 4,
                          width: area.width - 8, height: area.height - labelHeight - 8)
        let slot = plot.width / 24
        var out: [(Int, NSRect, Int)] = []
        for h in 0..<24 {
            let hgt = plot.height * CGFloat(s.averages[h]) / CGFloat(maxAvg)
            let r = NSRect(x: plot.minX + slot * CGFloat(h) + slot * 0.2,
                           y: plot.maxY - hgt,
                           width: slot * 0.6,
                           height: max(hgt, s.averages[h] > 0 ? 2 : 0))
            out.append((h, r, s.averages[h]))
        }
        return out
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let s = stats else { return }
        let bars = barRects()
        guard !bars.isEmpty else { return }

        // 基线
        let base = NSBezierPath()
        base.move(to: NSPoint(x: bounds.minX + 4, y: bounds.height - 20))
        base.line(to: NSPoint(x: bounds.maxX - 4, y: bounds.height - 20))
        NSColor.separatorColor.setStroke()
        base.lineWidth = 1
        base.stroke()

        let peakColor = accent
        let normalColor = NSColor.secondaryLabelColor.withAlphaComponent(0.55)
        for (h, r, avg) in bars where avg > 0 {
            let color = (h == s.peakHour) ? peakColor : normalColor
            color.setFill()
            NSBezierPath(roundedRect: r, xRadius: min(3, r.width / 2), yRadius: min(3, r.width / 2)).fill()
        }

        // 每 3 小时一个刻度
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 9.5, weight: .regular),
            .foregroundColor: NSColor.secondaryLabelColor
        ]
        for h in stride(from: 0, to: 24, by: 3) {
            let slot = (bounds.width - 8) / 24
            let x = bounds.minX + 4 + slot * CGFloat(h) + slot * 0.2
            let text = "\(h)点" as NSString
            text.draw(at: NSPoint(x: x, y: bounds.height - 16), withAttributes: attrs)
        }
    }
}

extension EditorRoot {

    /// 已并入「写作统计」：产量和节奏是同一个问题的两面，分两处看反而累
    @objc func showRhythmPanel(_ sender: Any?) {
        showStatsPanel(sender)
    }

    private func accentColorFor(_ preset: ThemePreset) -> NSColor {
        NSColor.systemOrange
    }
}
