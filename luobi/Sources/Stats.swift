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

    /// 统一的面板关闭入口：sheet 用 endSheet，独立窗口直接 close。
    /// （坑：对 sheet 调 performClose 不会结束 sheet，看起来就是"点了没反应"）
    @objc func dismissSheetPanel(_ sender: Any?) {
        // sender 可能是按钮（NSView）、也可能是面板自己（NSWindow）
        let win = (sender as? NSWindow) ?? (sender as? NSView)?.window ?? NSApp.keyWindow
        guard let target = win else { return }
        if let parent = target.sheetParent {
            parent.endSheet(target)
            // 关掉 sheet 后把主窗口和光标一起还回去，否则"第一下点击"会被吃掉
            DispatchQueue.main.async {
                parent.makeKey()
                if let editor = parent.contentView as? EditorRoot {
                    parent.makeFirstResponder(editor.textView)
                }
            }
        } else {
            target.close()
        }
    }

    /// 写作统计 = 30 天产量 + 一天里的节奏，合成一页
    /// （分成两个面板时，你得来回切着看——而这两件事本来就是同一个问题的两面）
    @objc func showStatsPanel(_ sender: Any?) {
        let stats = doc.writeStats(days: 30)
        let rhythm = doc.rhythm()
        let preset = ThemePresets.preset(doc.theme)
        let dim = preset.text.withAlphaComponent(0.62)
        let panel = LuobiSheetPanel(contentRect: NSRect(x: 0, y: 0, width: 720, height: 564),
                                    styleMask: [.titled, .closable],
                                    backing: .buffered, defer: false)
        panel.title = "写作统计"
        panel.isReleasedWhenClosed = false
        if preset.isDark { panel.appearance = NSAppearance(named: .darkAqua) }

        let body = NSView(frame: NSRect(x: 0, y: 0, width: 720, height: 520))
        body.wantsLayer = true
        body.layer?.backgroundColor = preset.bg.cgColor

        func text(_ str: String, size: CGFloat, weight: NSFont.Weight, color: NSColor,
                  y: CGFloat, h: CGFloat = 18, x: CGFloat = 28) -> NSTextField {
            let t = NSTextField(labelWithString: str)
            t.font = NSFont.systemFont(ofSize: size, weight: weight)
            t.textColor = color
            t.maximumNumberOfLines = 0
            t.frame = NSRect(x: x, y: y, width: 720 - x - 28, height: h)
            body.addSubview(t)
            return t
        }

        text("最近 30 天", size: 22, weight: .bold, color: preset.text, y: 470, h: 28)
        text("累计写作 \(stats.activeDays) 天 · 最长连续 \(stats.longestStreak) 天 · 本月 \(stats.monthWords) 字 · 总计 \(stats.totalWords) 字",
             size: 12, weight: .regular, color: dim, y: 446, h: 16)

        func minutes(_ sec: Int) -> String { sec < 60 ? "不到 1 分钟" : "\(sec / 60) 分钟" }
        text("今天写了 \(minutes(doc.todaySeconds)) · 近 7 天平均 \(minutes(doc.averageWriteSeconds(days: 7)))（只算真正打字的时间）"
             + (doc.todayPomodoros > 0 ? " · 今天 \(doc.todayPomodoros) 个番茄" : ""),
             size: 12, weight: .regular, color: dim, y: 426, h: 16)

        let chart = StatsChartView(frame: NSRect(x: 24, y: 214, width: 672, height: 196))
        chart.stats = stats
        chart.goal = doc.dailyGoal
        body.addSubview(chart)

        if doc.dailyGoal > 0 {
            text("橙色虚线 = 每日目标 \(doc.dailyGoal) 字", size: 10.5, weight: .regular,
                 color: NSColor.systemOrange.withAlphaComponent(0.9), y: 196, h: 14)
        }
        if stats.maxCount == 0 {
            text("还没有写作记录：今天写几句，明天这里就有第一根柱子。", size: 12, weight: .regular,
                 color: preset.text.withAlphaComponent(0.55), y: 330, h: 16)
        }

        let divider = NSBox(frame: NSRect(x: 28, y: 186, width: 664, height: 1))
        divider.boxType = .separator
        body.addSubview(divider)

        text("一天里的节奏 · 最近 \(max(1, rhythm.observedDays)) 天按小时平均", size: 14, weight: .semibold,
             color: preset.text, y: 160, h: 20)

        if rhythm.observedDays == 0 || rhythm.totals.max() == 0 {
            text("还没有按小时的记录：今天写一会儿，明天这里就有柱子了。", size: 12, weight: .regular, color: dim, y: 138, h: 16)
        } else {
            text("最出活：\(rhythm.peakHour) 点，平均每小时 \(rhythm.peakAvg) 字 · 最没效率：\(rhythm.lowHour) 点，平均 \(rhythm.lowAvg) 字",
                 size: 12.5, weight: .medium, color: preset.text, y: 138, h: 16)
            var insight = ""
            if let hook = rhythm.inflectionHour {
                let keep = rhythm.peakAvg > 0 ? Int(Double(rhythm.averages[hook]) / Double(rhythm.peakAvg) * 100) : 0
                insight = "拐点：\(hook) 点只剩峰值的 \(keep)% —— 这之后基本写不动了，适合收尾。"
            } else {
                insight = "拐点：样本还不够，多写几天就能看出你什么时候掉速。"
            }
            text(insight, size: 12, weight: .regular, color: NSColor.systemOrange, y: 120, h: 16)
            if rhythm.peakWPM > 0 {
                text("最快手速：\(rhythm.peakWPM) 字/分钟（连续 20 秒采样的峰值）", size: 11.5, weight: .regular, color: dim, y: 102, h: 16)
            }
            let rhythmChart = RhythmChartView(frame: NSRect(x: 24, y: 18, width: 672, height: 78))
            rhythmChart.stats = rhythm
            body.addSubview(rhythmChart)
        }

        body.translatesAutoresizingMaskIntoConstraints = false
        panel.contentView = wrapWithFooter(body, footerTitle: "完成")
        panel.onEsc = { [weak panel] in panel?.closeSelf() }
        presentSheet(panel)
    }
}
