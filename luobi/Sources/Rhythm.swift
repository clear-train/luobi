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

    @objc func showRhythmPanel(_ sender: Any?) {
        let stats = doc.rhythm()
        let preset = ThemePresets.preset(doc.theme)

        let panel = LuobiSheetPanel(contentRect: NSRect(x: 0, y: 0, width: 700, height: 430),
                            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        panel.title = "写作节奏"
        if preset.isDark { panel.appearance = NSAppearance(named: .darkAqua) }
        panel.isReleasedWhenClosed = false

        let content = NSView(frame: panel.contentView?.bounds ?? .zero)
        content.wantsLayer = true
        content.layer?.backgroundColor = preset.bg.cgColor
        panel.contentView = content

        func label(_ text: String, size: CGFloat, weight: NSFont.Weight, color: NSColor, y: CGFloat, h: CGFloat = 18) {
            let t = NSTextField(labelWithString: text)
            t.font = NSFont.systemFont(ofSize: size, weight: weight)
            t.textColor = color
            t.frame = NSRect(x: 24, y: y, width: 652, height: h)
            t.isBordered = false
            t.drawsBackground = false
            content.addSubview(t)
        }

        let dim = preset.text.withAlphaComponent(0.62)
        label("最近 \(max(1, stats.observedDays)) 天 · 按小时看产量", size: 15, weight: .semibold, color: preset.text, y: 388, h: 22)

        if stats.observedDays == 0 || stats.totals.max() == 0 {
            label("还没有按小时的记录：今天写一会儿，明天这里就有柱子了。", size: 12, weight: .regular, color: dim, y: 350)
        } else {
            let peakText = "最出活：\(stats.peakHour) 点，平均每小时 \(stats.peakAvg) 字"
            let lowText = "最没效率：\(stats.lowHour) 点，平均 \(stats.lowAvg) 字"
            label(peakText, size: 12.5, weight: .medium, color: preset.text, y: 366)
            label(lowText, size: 12.5, weight: .regular, color: dim, y: 346)

            var insight = ""
            if let hook = stats.inflectionHour {
                let keep = stats.peakAvg > 0 ? Int(Double(stats.averages[hook]) / Double(stats.peakAvg) * 100) : 0
                insight = "拐点：\(hook) 点只剩峰值的 \(keep)% —— 这个点之后基本写不动了，适合收尾。"
            } else {
                insight = "拐点：样本还不够，多写几天就能看出你什么时候掉速。"
            }
            label(insight, size: 12, weight: .regular, color: accentColorFor(preset), y: 326)

            if stats.peakWPM > 0 {
                label("最快手速：\(stats.peakWPM) 字/分钟（连续 20 秒采样的峰值）", size: 12, weight: .regular, color: dim, y: 306)
            }

            let chart = RhythmChartView(frame: NSRect(x: 24, y: 52, width: 652, height: 240))
            chart.stats = stats
            content.addSubview(chart)
        }

        let close = NSButton(title: "关闭", target: self, action: Selector(("dismissSheetPanel:")))
        close.bezelStyle = .texturedRounded
        close.keyEquivalent = "\r"
        close.frame = NSRect(x: 612, y: 12, width: 64, height: 26)
        content.addSubview(close)

        presentSheet(panel)
    }

    private func accentColorFor(_ preset: ThemePreset) -> NSColor {
        NSColor.systemOrange
    }
}
