import AppKit

// MARK: - 目标进度条（自绘，4pt 高）

final class GoalProgressTrack: NSView {

    var progress: Double = 0 { didSet { needsDisplay = true } }
    var reachedGoal: Bool = false { didSet { needsDisplay = true } }

    override func draw(_ dirtyRect: NSRect) {
        let h = bounds.height
        let radius = h / 2

        // 底轨
        let track = NSBezierPath(
            roundedRect: NSRect(x: 0, y: 0, width: bounds.width, height: h),
            xRadius: radius, yRadius: radius)
        NSColor.labelColor.withAlphaComponent(0.12).setFill()
        track.fill()

        // 进度填充
        let w = bounds.width * CGFloat(max(0, min(1, progress)))
        guard w > 0 else { return }
        let r = min(radius, w / 2)
        let fill = NSBezierPath(
            roundedRect: NSRect(x: 0, y: 0, width: w, height: h),
            xRadius: r, yRadius: r)
        (reachedGoal ? NSColor.systemGreen : NSColor.systemBlue).setFill()
        fill.fill()
    }
}

// MARK: - EditorRoot 扩展：安装 / 刷新 / 设定对话框

extension EditorRoot {

    private var gaugeGoalBar: GoalProgressTrack? {
        subviews.compactMap { $0 as? GoalProgressTrack }.first
    }

    @objc func installGoalBar(_ sender: Any?) {
        guard gaugeGoalBar == nil else { return }
        let bar = GoalProgressTrack()
        bar.translatesAutoresizingMaskIntoConstraints = false
        bar.isHidden = (doc.goal <= 0)
        addSubview(bar)
        NSLayoutConstraint.activate([
            bar.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            bar.trailingAnchor.constraint(equalTo: trailingAnchor),
            bar.bottomAnchor.constraint(equalTo: barLabel.topAnchor, constant: -4),
            bar.heightAnchor.constraint(equalToConstant: 4),
        ])
        bar.needsDisplay = true
    }

    @objc func refreshGoalProgress(_ sender: Any?) {
        if gaugeGoalBar == nil { installGoalBar(sender) }
        guard let bar = gaugeGoalBar else { return }
        // 专注/阅读是「只剩正文」的状态，进度条也一起藏起来
        bar.isHidden = focusMode || readingMode
        // 优先用「今日目标」：写小说最需要的是今天有没有推进，而不是全书总量
        if doc.dailyGoal > 0 {
            bar.isHidden = focusMode || readingMode
            let n = doc.todayWritten
            bar.progress = min(1, Double(n) / Double(doc.dailyGoal))
            bar.reachedGoal = (n >= doc.dailyGoal)
            return
        }
        let goal = doc.goal
        bar.isHidden = (goal <= 0) || focusMode || readingMode
        guard goal > 0 else { return }
        let n = statCJK(textView.string) + statLatin(textView.string)
        bar.progress = min(1, Double(n) / Double(goal))
        bar.reachedGoal = (n >= goal)
    }

    /// 写作目标面板：今日进度 + 连续达标 + 设定每日目标
    @objc func showGoalPanel(_ sender: Any?) {
        let alert = NSAlert()
        alert.messageText = "今日写作"
        let n = doc.todayWritten
        let goal = max(doc.dailyGoal, doc.goal)
        let goalText = doc.dailyGoal > 0 ? "\(doc.dailyGoal) 字" : "未设定"
        alert.informativeText = "今天写了 \(n) 字 ；目标 \(goalText)；连续达标 \(doc.dailyStreak) 天"

        let track = GoalProgressTrack()
        track.translatesAutoresizingMaskIntoConstraints = false
        track.heightAnchor.constraint(equalToConstant: 6).isActive = true
        track.widthAnchor.constraint(equalToConstant: 320).isActive = true
        if goal > 0 {
            track.progress = min(1, Double(n) / Double(goal))
            track.reachedGoal = n >= goal
        }

        let field = NSTextField()
        field.placeholderString = "每天多少字，例如 500（0 = 不设）"
        field.stringValue = doc.dailyGoal > 0 ? String(doc.dailyGoal) : ""
        field.translatesAutoresizingMaskIntoConstraints = false
        field.widthAnchor.constraint(equalToConstant: 240).isActive = true

        let stack = NSStackView(views: [track, field])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.frame = NSRect(x: 0, y: 0, width: 320, height: 48)
        alert.accessoryView = stack

        alert.addButton(withTitle: "保存")
        alert.addButton(withTitle: "取消")

        let apply: (NSApplication.ModalResponse) -> Void = { [weak self] resp in
            guard let self = self, resp == .alertFirstButtonReturn else { return }
            let text = field.stringValue.trimmingCharacters(in: .whitespaces)
            self.doc.dailyGoal = max(0, Int(text) ?? 0)
            if self.doc.dailyGoal > 0 { self.doc.ensureDailyBase() }
            self.persistNow()
            self.refreshGoalProgress(nil)
        }

        if let win = window {
            alert.beginSheetModal(for: win, completionHandler: apply)
        } else {
            apply(alert.runModal())
        }
    }

    /// 旧入口保留：侧栏底部「写作目标」按钮与菜单都还能用
    @objc func setGoalDialog(_ sender: Any?) { showGoalPanel(sender) }
}
