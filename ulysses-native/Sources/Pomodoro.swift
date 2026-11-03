import AppKit

// MARK: - 番茄钟
//
// 设计取舍：
//   1. 25 分钟专注 + 5 分钟休息，不提供自定义（选择本身就是拖延的来源）
//   2. 不弹窗打断正在打的字：只在计时结束时弹一次，且"继续写"是默认的退路
//   3. 只统计"专注"完成，休息不算成绩 —— 否则一天点 20 次休息也变 20 个番茄
//   4. 番茄数和写作时长进同一份 state.json，跟文稿一起备份

private let pomoFocusSeconds = 25 * 60
private let pomoBreakSeconds = 5 * 60

extension EditorRoot {

    /// 工具栏按钮：未开始显示 25:00，运行中显示剩余时间
    @objc func togglePomodoro(_ sender: Any?) {
        if pomoEndAt != nil {
            pausePomodoro()
        } else {
            startPomodoro(isBreak: false)
        }
    }

    func startPomodoro(isBreak: Bool) {
        pomoIsBreak = isBreak
        pomoEndAt = Date().addingTimeInterval(TimeInterval(isBreak ? pomoBreakSeconds : pomoFocusSeconds))
        pomoTimer?.invalidate()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            self?.tickPomodoro()
        }
        // .common：拖动侧栏、滚动正文时计时也不能停
        RunLoop.main.add(timer, forMode: .common)
        pomoTimer = timer
        updatePomodoroButton()
        startupNote = isBreak ? "休息 5 分钟，别碰稿子" : "开始 25 分钟专注"
        refreshBar()
    }

    func pausePomodoro() {
        pomoTimer?.invalidate()
        pomoTimer = nil
        pomoEndAt = nil
        updatePomodoroButton()
        startupNote = "番茄钟已暂停"
        refreshBar()
    }

    func tickPomodoro() {
        guard let end = pomoEndAt else { return }
        let left = Int(end.timeIntervalSinceNow.rounded(.up))
        if left <= 0 {
            finishPomodoro()
        } else {
            updatePomodoroButton()
        }
    }

    /// 收尾（不弹窗）：返回刚刚结束的是不是休息段。测试直接调它，UI 走 finishPomodoro。
    @discardableResult
    func closePomodoro() -> Bool {
        let wasBreak = pomoIsBreak
        pomoTimer?.invalidate()
        pomoTimer = nil
        pomoEndAt = nil
        updatePomodoroButton()
        if !wasBreak {
            doc.addPomodoro()
            persistNow()
        }
        return wasBreak
    }

    func finishPomodoro() {
        let wasBreak = closePomodoro()
        NSSound(named: "Glass")?.play()

        let alert = NSAlert()
        if wasBreak {
            alert.messageText = "休息结束"
            alert.informativeText = "回来写吧。再来一个 25 分钟？今天已完成 \(doc.todayPomodoros) 个番茄。"
            alert.addButton(withTitle: "再来一个")
            alert.addButton(withTitle: "稍后")
            if alert.runModal() == .alertFirstButtonReturn { startPomodoro(isBreak: false) }
        } else {
            alert.messageText = "25 分钟到了"
            alert.informativeText = "站起来走两步、喝口水，眼睛看远处二十秒。今天已完成 \(doc.todayPomodoros) 个番茄。"
            alert.addButton(withTitle: "休息 5 分钟")
            alert.addButton(withTitle: "继续写")
            if alert.runModal() == .alertFirstButtonReturn {
                startPomodoro(isBreak: true)
            } else {
                startupNote = "继续写：今天已完成 \(doc.todayPomodoros) 个番茄"
                refreshBar()
            }
        }
    }

    func updatePomodoroButton() {
        guard let b = pomoButton else { return }
        guard let end = pomoEndAt else {
            b.title = "🍅"
            b.toolTip = "番茄钟：25 分钟专注 + 5 分钟休息"
            return
        }
        let left = max(0, Int(end.timeIntervalSinceNow.rounded(.up)))
        b.title = String(format: "%@ %02d:%02d", pomoIsBreak ? "☕︎" : "🍅", left / 60, left % 60)
        b.toolTip = pomoIsBreak ? "休息中，点一下暂停" : "专注中，点一下暂停"
    }
}
