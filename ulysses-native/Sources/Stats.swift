import AppKit

// MARK: - 写作统计：最近 30 天的字数柱状图
//
// 为什么先做这个而不是继续加导出格式：
// 写作最难的从来不是"交出去"，是"今天坐下来"。看得见的曲线比功能更能把人按在椅子上。

final class StatsChartView: NSView {

    var stats = WriteStats() { didSet { needsDisplay = true } }
    var goal: Int = 0 { didSet { needsDisplay = true } }

    var onDayClick: ((DayCount) -> Void)?

    private let bottomInset: CGFloat = 26
    private let topInset: CGFloat = 18

    override var isFlipped: Bool { false }

    /// 柱子的矩形（测试和绘制共用一套算法，避免"画的和算的不一致"）
    func barRects() -> [(DayCount, NSRect)] {
        let n = stats.days.count
        guard n > 0, bounds.width > 0, bounds.height > 0 else { return [] }
        let plotW = bounds.width - 8
        let plotH = bounds.height - bottomInset - topInset
        let maxV = max(stats.maxCount, goal, 1)
        let slot = plotW / CGFloat(n)
        let barW = max(2, min(16, slot * 0.62))
        return stats.days.enumerated().map { (i, day) in
            let h = plotH * CGFloat(day.count) / CGFloat(maxV)
            let x = 4 + slot * (CGFloat(i) + 0.5) - barW / 2
            return (day, NSRect(x: x, y: bottomInset, width: barW, height: max(day.count > 0 ? 2 : 0, h)))
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current else { return }
        ctx.saveGraphicsState()

        let plotH = bounds.height - bottomInset - topInset
        let baseY = bottomInset

        // 基线
        NSColor.labelColor.withAlphaComponent(0.10).setFill()
        NSRect(x: 0, y: baseY - 0.5, width: bounds.width, height: 1).fill()

        // 目标线（虚线）
        if goal > 0, stats.maxCount > 0 || goal > 0 {
            let maxV = CGFloat(max(stats.maxCount, goal, 1))
            let y = baseY + plotH * CGFloat(goal) / maxV
            if y > baseY {
                let path = NSBezierPath()
                path.move(to: NSPoint(x: 0, y: y))
                path.line(to: NSPoint(x: bounds.width, y: y))
                path.setLineDash([3, 3], count: 2, phase: 0)
                path.lineWidth = 1
                NSColor.systemOrange.withAlphaComponent(0.55).setStroke()
                path.stroke()
            }
        }

        let bars = barRects()
        let todayKey = dayKey()
        for (day, r) in bars {
            let reached = goal > 0 && day.count >= goal
            let isToday = day.key == todayKey
            let color: NSColor
            if isToday {
                color = reached ? .systemGreen : .systemBlue
            } else {
                color = reached ? .systemGreen.withAlphaComponent(0.85) : .systemBlue.withAlphaComponent(0.62)
            }
            color.setFill()
            let path = NSBezierPath(roundedRect: r, xRadius: min(2.5, r.width / 2), yRadius: min(2.5, r.width / 2))
            path.fill()
        }

        // 日期标签：每 5 天一个，今天单独标
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 8.5),
            .foregroundColor: NSColor.secondaryLabelColor,
        ]
        let df = DateFormatter()
        df.dateFormat = "M/d"
        for (i, day) in stats.days.enumerated() {
            let isToday = day.key == todayKey
            guard i % 5 == 0 || isToday else { continue }
            let label = isToday ? "今天" : df.string(from: day.date)
            let size = (label as NSString).size(withAttributes: attrs)
            let centerX = bars.isEmpty ? 0 : bars[i].1.midX
            let x = min(max(2, centerX - size.width / 2), bounds.width - size.width - 2)
            (label as NSString).draw(at: NSPoint(x: x, y: 6), withAttributes: attrs)
        }

        ctx.restoreGraphicsState()
    }
}

// MARK: - 面板

extension EditorRoot {

    @objc func showStatsPanel(_ sender: Any?) {
        let stats = doc.writeStats(days: 30)
        let goal = doc.dailyGoal

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 380),
            styleMask: [.titled, .closable],
            backing: .buffered, defer: false)
        panel.title = "写作统计"
        if ThemePresets.preset(doc.theme).isDark { panel.appearance = NSAppearance(named: .darkAqua) }
        panel.isReleasedWhenClosed = false

        let content = NSView(frame: panel.contentView?.bounds ?? .zero)
        content.wantsLayer = true
        let preset = ThemePresets.preset(doc.theme)
        content.layer?.backgroundColor = preset.bg.cgColor
        panel.contentView = content

        func label(_ text: String, _ size: CGFloat, _ weight: NSFont.Weight, _ color: NSColor, y: CGFloat, h: CGFloat = 20) -> NSTextField {
            let t = NSTextField(labelWithString: text)
            t.font = NSFont.systemFont(ofSize: size, weight: weight)
            t.textColor = color
            t.frame = NSRect(x: 24, y: y, width: 592, height: h)
            t.isBordered = false
            t.drawsBackground = false
            content.addSubview(t)
            return t
        }

        _ = label("最近 30 天", 15, .semibold, preset.text, y: 332, h: 22)
        _ = label("累计写作 \(stats.activeDays) 天 · 最长连续 \(stats.longestStreak) 天 · 本月 \(stats.monthWords) 字 · 总计 \(stats.totalWords) 字",
                  12, .regular, preset.text.withAlphaComponent(0.62), y: 310, h: 18)

        // 时间维度：字数是结果，时长才是习惯
        func minutes(_ sec: Int) -> String { sec < 60 ? "不到 1 分钟" : "\(sec / 60) 分钟" }
        _ = label("今天写了 \(minutes(doc.todaySeconds)) · 近 7 天平均 \(minutes(doc.averageWriteSeconds(days: 7)))（只统计真正在打字的时间）",
                  12, .regular, preset.text.withAlphaComponent(0.62), y: 292, h: 16)

        let chart = StatsChartView(frame: NSRect(x: 20, y: 58, width: 600, height: 240))
        chart.stats = stats
        chart.goal = goal
        content.addSubview(chart)

        if stats.maxCount == 0 {
            _ = label("还没有写作记录：今天写几句，明天这里就有第一根柱子。", 12, .regular,
                      preset.text.withAlphaComponent(0.55), y: 300, h: 18)
        }
        if goal > 0 {
            _ = label("橙色虚线 = 每日目标 \(goal) 字", 10.5, .regular,
                      NSColor.systemOrange.withAlphaComponent(0.9), y: 40, h: 14)
        }

        let close = NSButton(title: "关闭", target: nil, action: nil)
        close.bezelStyle = .texturedRounded
        close.keyEquivalent = "\r"
        close.frame = NSRect(x: 552, y: 10, width: 64, height: 26)
        close.target = close
        close.action = #selector(NSWindow.performClose(_:))
        content.addSubview(close)

        if let win = window {
            win.beginSheet(panel) { _ in }
        } else {
            panel.center()
            panel.makeKeyAndOrderFront(nil)
        }
    }
}
