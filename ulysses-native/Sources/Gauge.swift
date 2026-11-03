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
        let goal = doc.goal
        bar.isHidden = (goal <= 0)
        guard goal > 0 else { return }
        let n = statCJK(textView.string) + statLatin(textView.string)
        bar.progress = min(1, Double(n) / Double(goal))
        bar.reachedGoal = (n >= goal)
    }

    @objc func setGoalDialog(_ sender: Any?) {
        let alert = NSAlert()
        alert.messageText = "设定写作目标字数"
        alert.informativeText = "达到目标后进度条变绿；清除则不再显示进度条。"
        let field = NSTextField()
        field.placeholderString = "总字数，例如 1000"
        field.stringValue = (doc.goal > 0) ? String(doc.goal) : ""
        field.translatesAutoresizingMaskIntoConstraints = false
        field.widthAnchor.constraint(equalToConstant: 180).isActive = true
        alert.accessoryView = field
        alert.addButton(withTitle: "设定")
        alert.addButton(withTitle: "清除(0)")
        alert.addButton(withTitle: "取消")

        let apply: (NSApplication.ModalResponse) -> Void = { [weak self] resp in
            guard let self = self else { return }
            switch resp {
            case .alertFirstButtonReturn:
                let text = field.stringValue.trimmingCharacters(in: .whitespaces)
                self.doc.goal = max(0, Int(text) ?? 0)
            case .alertSecondButtonReturn:
                self.doc.goal = 0
            default:
                return
            }
            self.persistNow()
            self.refreshGoalProgress(nil)
        }

        if let win = window {
            alert.beginSheetModal(for: win, completionHandler: apply)
        } else {
            apply(alert.runModal())
        }
    }
}
