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

        if wasBreak {
            // 休息结束也只用软提示：不打断，让它自己消失
            showToast(title: "休息结束",
                      detail: "回来写吧。今天已完成 \(doc.todayPomodoros) 个番茄。",
                      seconds: 14,
                      buttons: [("再来一个", Selector(("startPomodoroFromMenu:"))),
                                ("稍后", Selector(("dismissToast:")))])
        } else {
            showToast(title: "25 分钟到了",
                      detail: "站起来走两步、喝口水，看一会儿远处。今天已完成 \(doc.todayPomodoros) 个番茄。",
                      seconds: 18,
                      buttons: [("休息 5 分钟", Selector(("startBreakFromToast:"))),
                                ("继续写", Selector(("dismissToast:")))])
        }
        startupNote = "25 分钟专注完成 · 今天 \(doc.todayPomodoros) 个番茄"
        refreshBar()
    }

    @objc func startBreakFromToast(_ sender: Any?) {
        dismissToast()
        startPomodoro(isBreak: true)
    }

    func updatePomodoroButton() {
        if let end = pomoEndAt {
            let total: CGFloat = pomoIsBreak ? 300 : 1500
            let left = max(0, end.timeIntervalSinceNow)
            let p = 1 - CGFloat(left) / total
            pomoButton?.ringProgress = p
            pomoButton?.ringColor = pomoIsBreak ? .systemBlue : .systemRed
            pomoButton?.glyph = pomoIsBreak ? "☕" : "番"
            pomoButton?.toolTip = (pomoIsBreak ? "休息中" : "专注中") + "，还剩 " + String(format: "%02d:%02d", Int(left) / 60, Int(left) % 60) + "，点一下暂停"
        } else {
            pomoButton?.ringProgress = 0
            pomoButton?.ringColor = .systemRed
            pomoButton?.glyph = "番"
            pomoButton?.toolTip = "番茄钟：点一下开始 25 分钟专注"
        }
        refreshStatusItem()
    }
}
