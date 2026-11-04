import AppKit

// MARK: - 今日页
//
// 浮层（hover）适合"瞟一眼"，但想认真看今天怎么过的，需要一块地方。
// 这里只回答一个问题：今天这一天，是什么形状的。

extension DocState {
    /// 今天每小时的净字数（0–23）
    func todayHourly() -> [Int] {
        let prefix = dayKey() + " "
        var out = [Int](repeating: 0, count: 24)
        for (k, v) in hourlyWords where k.hasPrefix(prefix) {
            let hh = k.suffix(2)
            if let h = Int(hh), h >= 0, h < 24 { out[h] += max(0, v) }
        }
        return out
    }
}

/// 今天 24 根柱子：什么时候在写、什么时候空着，一眼能看出来
final class TodayCurveView: NSView {
    var hours: [Int] = []
    var accent: NSColor = .systemOrange
    var muted: NSColor = .labelColor

    override var isFlipped: Bool { true }

    func barRects(in rect: NSRect = .zero) -> [(hour: Int, rect: NSRect, words: Int)] {
        let area = rect == .zero ? bounds : rect
        guard hours.count == 24 else { return [] }
        let labelHeight: CGFloat = 18
        let plot = NSRect(x: area.minX + 8, y: area.minY + 6,
                          width: area.width - 16, height: area.height - labelHeight - 6)
        let maxWords = max(1, hours.max() ?? 1)
        let slot = plot.width / 24
        let barW = max(3, slot * 0.58)
        var out: [(Int, NSRect, Int)] = []
        for h in 0..<24 {
            let v = hours[h]
            let hRatio = CGFloat(v) / CGFloat(maxWords)
            let height = max(v > 0 ? 3 : 1, plot.height * hRatio)
            let x = plot.minX + slot * CGFloat(h) + (slot - barW) / 2
            let y = plot.maxY - height
            out.append((h, NSRect(x: x, y: y, width: barW, height: height), v))
        }
        return out
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let now = Calendar.current.component(.hour, from: Date())
        for (h, r, v) in barRects() {
            let color = v > 0 ? accent.withAlphaComponent(h == now ? 1.0 : 0.75)
                              : muted.withAlphaComponent(0.12)
            color.setFill()
            NSBezierPath(roundedRect: r, xRadius: 2, yRadius: 2).fill()
        }
        let font = NSFont.systemFont(ofSize: 10)
        let attrs: [NSAttributedString.Key: Any] = [.font: font,
                                                    .foregroundColor: muted.withAlphaComponent(0.5)]
        for h in [0, 6, 12, 18, 23] {
            let s = NSAttributedString(string: h == 0 ? "0 点" : "\(h)", attributes: attrs)
            let w = s.size().width
            let slot = (bounds.width - 16) / 24
            let x = 8 + slot * CGFloat(h) + (slot - w) / 2
            s.draw(at: NSPoint(x: x, y: bounds.height - 16))
        }
    }
}

extension EditorRoot {

    /// 今天这一页：数字 + 曲线 + 一句判断
    @objc func showTodayPanel(_ sender: Any?) {
        let preset = ThemePresets.preset(doc.theme)
        let panel = LuobiSheetPanel(contentRect: NSRect(x: 0, y: 0, width: 700, height: 430),
                                    styleMask: [.titled, .closable],
                                    backing: .buffered, defer: false)
        panel.title = "今天"
        panel.isReleasedWhenClosed = false
        if preset.isDark { panel.appearance = NSAppearance(named: .darkAqua) }

        let body = NSView(frame: NSRect(x: 0, y: 0, width: 700, height: 386))
        body.wantsLayer = true
        body.layer?.backgroundColor = preset.bg.cgColor

        let df = DateFormatter()
        df.locale = Locale(identifier: "zh_CN")
        df.dateFormat = "M 月 d 日 EEEE"
        let head = NSTextField(labelWithString: "今天 · " + df.string(from: Date()))
        head.font = Typo.bold(22)
        head.textColor = preset.text
        head.translatesAutoresizingMaskIntoConstraints = false
        body.addSubview(head)

        let hours = doc.todayHourly()
        let total = hours.reduce(0, +)
        let bestHour = hours.enumerated().max { $0.element < $1.element }
        let activeHours = hours.filter { $0 > 0 }.count
        var facts: [String] = []
        if doc.dailyGoal > 0 {
            let pct = min(999, Int(Double(doc.todayWritten) / Double(doc.dailyGoal) * 100))
            facts.append("目标 \(doc.todayWritten)/\(doc.dailyGoal) 字 · 完成 \(pct)%")
        } else {
            facts.append("今天 \(doc.todayWritten) 字 · 还没设每日目标")
        }
        if doc.showSpeed, doc.todaySeconds > 30, doc.todayWritten > 0 {
            let rate = Double(doc.todayWritten) * 60 / Double(max(1, doc.todaySeconds))
            let rateText = rate < 10 ? String(format: "%.1f", rate) : String(format: "%.0f", rate)
            facts.append("速度 \(rateText) 字/分钟 · 专注 \(doc.todaySeconds / 60) 分钟")
        }
        if doc.showEffect, doc.todayPomodoros > 0 {
            facts.append("效率 · 每个番茄 \(doc.todayWritten / doc.todayPomodoros) 字 · 共 \(doc.todayPomodoros) 个")
        }
        if doc.shadowMode {
            let sh = doc.shadow()
            facts.append(sh.hasHistory
                         ? "影子 · 过去的你这会儿 \(sh.expected) 字，你 \(sh.actual) 字（\(sh.verdict)）"
                         : "影子 · 再写几天就有参照了")
        }
        facts.append("今天有 \(activeHours) 个小时在写" +
                     (total > 0 && bestHour.map { $0.element > 0 } == true
                      ? " · 最出活的是 \(bestHour!.offset) 点（\(bestHour!.element) 字）" : ""))

        let factsText = NSTextField(labelWithString: facts.joined(separator: "\n"))
        factsText.font = NSFont.systemFont(ofSize: 12.5)
        factsText.textColor = preset.text.withAlphaComponent(0.72)
        factsText.maximumNumberOfLines = 0
        factsText.translatesAutoresizingMaskIntoConstraints = false
        body.addSubview(factsText)

        let curve = TodayCurveView()
        curve.hours = hours
        curve.accent = preset.isDark ? .systemGreen : .systemOrange
        curve.muted = preset.text
        curve.translatesAutoresizingMaskIntoConstraints = false
        body.addSubview(curve)

        let hint = NSTextField(labelWithString: total > 0
            ? "柱子是每小时净增的字。空白不是罪——写作本来就是一段一段的。"
            : "今天还没有记录。打开正文写几句，这里就会长出第一根柱子。")
        hint.font = NSFont.systemFont(ofSize: 11)
        hint.textColor = preset.text.withAlphaComponent(0.5)
        hint.maximumNumberOfLines = 0
        hint.translatesAutoresizingMaskIntoConstraints = false
        body.addSubview(hint)

        NSLayoutConstraint.activate([
            head.leadingAnchor.constraint(equalTo: body.leadingAnchor, constant: 28),
            head.topAnchor.constraint(equalTo: body.topAnchor, constant: 24),
            factsText.leadingAnchor.constraint(equalTo: head.leadingAnchor),
            factsText.trailingAnchor.constraint(equalTo: body.trailingAnchor, constant: -28),
            factsText.topAnchor.constraint(equalTo: head.bottomAnchor, constant: 14),
            curve.leadingAnchor.constraint(equalTo: head.leadingAnchor),
            curve.trailingAnchor.constraint(equalTo: body.trailingAnchor, constant: -28),
            curve.topAnchor.constraint(equalTo: factsText.bottomAnchor, constant: 18),
            curve.heightAnchor.constraint(equalToConstant: 170),
            hint.leadingAnchor.constraint(equalTo: head.leadingAnchor),
            hint.trailingAnchor.constraint(equalTo: body.trailingAnchor, constant: -28),
            hint.topAnchor.constraint(equalTo: curve.bottomAnchor, constant: 10)
        ])

        body.translatesAutoresizingMaskIntoConstraints = false
        panel.contentView = wrapWithFooter(body, footerTitle: "完成")
        panel.onEsc = { [weak panel] in panel?.closeSelf() }
        presentSheet(panel)
    }
}
