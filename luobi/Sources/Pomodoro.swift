import AppKit

// MARK: - 番茄钟（倒计时 → 到点后自动转正计时）
//
// 设计取舍：
//   1. 倒计时不是"结束"，是"提醒"。到点后**不打断、不强制停**，
//      自动切成正计时（加班时间），环变橙色，你可以继续写到收尾。
//   2. 暂停 = 冻结已用时间；再点继续，从冻结处往下走。不会丢进度。
//   3. 专注时长/休息时长可以自己设，默认 25/5。
//   4. 只统计"写满一个完整专注段"的番茄，休息和提前结束不算成绩。

extension EditorRoot {

    /// 当前这一段的总长度（秒）
    var pomoDuration: TimeInterval {
        TimeInterval(max(1, pomoIsBreak ? doc.breakMinutes : doc.focusMinutes) * 60)
    }

    /// 这一段真正用掉的时间：暂停时冻结的部分 + 本次运行的部分
    var pomoElapsed: TimeInterval {
        var e = pomoSpent
        if pomoRunning, let start = pomoStartAt {
            e += Date().timeIntervalSince(start)
        }
        return max(0, e)
    }

    /// 倒计时剩余（到 0 之后一直是 0）
    var pomoRemaining: TimeInterval { max(0, pomoDuration - pomoElapsed) }

    /// 超时后的正计时
    var pomoOvertime: TimeInterval { max(0, pomoElapsed - pomoDuration) }

    /// 有未结束的一段（运行中或暂停中）
    var hasPomoSession: Bool { pomoRunning || pomoSpent > 0 }

    var pomoIsOvertime: Bool { hasPomoSession && pomoElapsed >= pomoDuration }

    // MARK: 操作

    /// 设置里关掉番茄钟后，顶栏的 🍅 环应该整个消失（不只是变灰）
    func applyPomodoroVisibility() {
        pomoButton?.isHidden = !doc.pomodoroEnabled
    }

    @objc func togglePomodoro(_ sender: Any?) {
        if pomoRunning {
            pausePomodoro()
        } else if hasPomoSession {
            resumePomodoro()
        } else {
            startPomodoro(isBreak: false)
        }
    }

    func startPomodoro(isBreak: Bool) {
        pomoStartWords = totalWords(doc)
        pomoIsBreak = isBreak
        pomoSpent = 0
        pomoStartAt = Date()
        pomoRunning = true
        pomoNotified = false
        startPomoTimer()
        updatePomodoroButton()
        let mins = Int(pomoDuration / 60)
        startupNote = isBreak ? "休息 \(mins) 分钟，别碰稿子" : "开始 \(mins) 分钟专注"
        refreshBar()
    }

    /// 暂停：把已用时间冻结下来，再点继续接着走
    func pausePomodoro() {
        guard pomoRunning else { return }
        pomoSpent = pomoElapsed
        pomoStartAt = nil
        pomoRunning = false
        pomoTimer?.invalidate()
        pomoTimer = nil
        updatePomodoroButton()
        startupNote = "已暂停 · 还剩 " + pomoRemainingText
        refreshBar()
    }

    func resumePomodoro() {
        guard !pomoRunning, hasPomoSession else { return }
        pomoStartAt = Date()
        pomoRunning = true
        startPomoTimer()
        updatePomodoroButton()
        startupNote = "继续 · 还剩 " + pomoRemainingText
        refreshBar()
    }

    private func startPomoTimer() {
        pomoTimer?.invalidate()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            self?.tickPomodoro()
        }
        // .common：拖动侧栏、滚动正文时计时也不能停
        RunLoop.main.add(timer, forMode: .common)
        pomoTimer = timer
    }

    func tickPomodoro() {
        guard pomoRunning else { return }
        // 到点只提醒一次，之后继续正计时（不强制结束）
        if !pomoNotified, pomoElapsed >= pomoDuration {
            pomoNotified = true
            NSSound(named: "Glass")?.play()
            if pomoIsBreak {
                showToast(title: "休息结束",
                          detail: "回来写吧。今天已完成 \(doc.todayPomodoros) 个番茄。",
                          seconds: 12,
                          buttons: [("再来一个", Selector(("startPomodoroFromMenu:"))),
                                    ("稍后", Selector(("dismissToast:")))])
            } else {
                doc.addPomodoro()
                persistNow()
                let wrote = max(0, totalWords(doc) - pomoStartWords)
                var detail = "这一段时间写了 \(wrote) 字。现在开始正计时——想停就停，想接着写也算。今天已完成 \(doc.todayPomodoros) 个番茄。"
                if shadowModeEnabled {
                    let sh = doc.shadow()
                    if sh.hasHistory {
                        detail += "\n影子：过去的你这会儿 \(sh.expected) 字，你 \(sh.actual) 字（\(sh.verdict)）"
                    }
                }
                showToast(title: "\(Int(pomoDuration / 60)) 分钟到了",
                          detail: detail,
                          seconds: 16,
                          buttons: [("休息 \(doc.breakMinutes) 分钟", Selector(("startBreakFromToast:"))),
                                    ("继续写（正计时）", Selector(("dismissToast:")))])
            }
        }
        updatePomodoroButton()
    }

    /// 结束当前这一段（不弹提示）：返回刚刚结束的是不是休息段
    @discardableResult
    func closePomodoro() -> Bool {
        let wasBreak = pomoIsBreak
        pomoTimer?.invalidate()
        pomoTimer = nil
        pomoRunning = false
        pomoStartAt = nil
        pomoSpent = 0
        pomoNotified = false
        updatePomodoroButton()
        return wasBreak
    }

    func finishPomodoro() {
        _ = closePomodoro()
        NSSound(named: "Glass")?.play()
        updatePomodoroButton()
        refreshBar()
    }

    @objc func startBreakFromToast(_ sender: Any?) {
        dismissToast()
        startPomodoro(isBreak: true)
    }

    @objc func startPomodoroFromMenu(_ sender: Any?) {
        startPomodoro(isBreak: false)
    }

    // MARK: 显示

    func updatePomodoroButton() {
        guard let btn = pomoButton else { refreshStatusItem(); return }
        if !hasPomoSession {
            btn.ringProgress = 0
            btn.ringColor = .systemRed
            btn.glyph = "T"
            btn.toolTip = "番茄钟：点一下开始 \(doc.focusMinutes) 分钟专注"
        } else {
            let p = min(1, CGFloat(pomoElapsed / pomoDuration))
            btn.ringProgress = p
            if pomoIsOvertime {
                btn.ringColor = .systemOrange
                btn.glyph = "+"
                btn.toolTip = "已超时 " + pomoOvertimeText + "（正计时中），点一下暂停"
            } else if pomoIsBreak {
                btn.ringColor = .systemBlue
                btn.glyph = "☕"
                btn.toolTip = (pomoRunning ? "休息中" : "休息暂停") + "，还剩 " + pomoRemainingText + "，点一下" + (pomoRunning ? "暂停" : "继续")
            } else {
                btn.ringColor = .systemRed
                btn.glyph = "T"
                btn.toolTip = (pomoRunning ? "专注中" : "已暂停") + "，还剩 " + pomoRemainingText + "，点一下" + (pomoRunning ? "暂停" : "继续")
            }
        }
        refreshStatusItem()
    }

    /// 设置专注/休息时长
    @objc func showPomodoroSettings(_ sender: Any?) {
        let alert = NSAlert()
        alert.messageText = "番茄钟时长"
        alert.informativeText = "默认 25 分钟专注、5 分钟休息。到点后会继续正计时，不会强行中断。"
        alert.addButton(withTitle: "保存")
        alert.addButton(withTitle: "恢复默认")
        alert.addButton(withTitle: "取消")

        let focusField = makeNumberField(doc.focusMinutes, tag: 1)
        let breakField = makeNumberField(doc.breakMinutes, tag: 2)
        let grid = NSGridView(views: [
            [NSTextField(labelWithString: "专注（分钟）"), focusField],
            [NSTextField(labelWithString: "休息（分钟）"), breakField]
        ])
        grid.rowSpacing = 8
        grid.columnSpacing = 10
        grid.frame = NSRect(x: 0, y: 0, width: 240, height: 60)
        alert.accessoryView = grid

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            doc.focusMinutes = min(180, max(1, Int(focusField.stringValue) ?? doc.focusMinutes))
            doc.breakMinutes = min(180, max(1, Int(breakField.stringValue) ?? doc.breakMinutes))
            persistNow()
            startupNote = "番茄钟：专注 \(doc.focusMinutes) 分 / 休息 \(doc.breakMinutes) 分"
        } else if response == .alertSecondButtonReturn {
            doc.focusMinutes = 25
            doc.breakMinutes = 5
            persistNow()
            startupNote = "番茄钟已恢复 25 / 5"
        }
        updatePomodoroButton()
        refreshBar()
    }

    private func makeNumberField(_ value: Int, tag: Int) -> NSTextField {
        let f = NSTextField(string: String(value))
        f.tag = tag
        f.alignment = .right
        f.frame = NSRect(x: 0, y: 0, width: 70, height: 22)
        return f
    }
}
