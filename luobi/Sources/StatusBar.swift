import AppKit

// MARK: - 菜单栏（系统栏）状态项 + 图形化进度
//
// 用户反馈：「上方功能太多，不一定都显示在这里，放在系统栏里」。
// 所以主窗口顶栏只留最常用的三个（新建/分组/侧栏）+ 两个环，
// 其余动作全部收进 macOS 菜单栏的那个图标里——它一直在，也不占窗口宽度。

extension NSImage {
    /// 画一个进度环，可选中间放一个字/符号（番茄、今）
    static func ring(progress: CGFloat,
                     color: NSColor,
                     size: CGFloat = 20,
                     glyph: String? = nil,
                     glyphFont: CGFloat = 9) -> NSImage {
        let s = NSSize(width: size, height: size)
        let img = NSImage(size: s, flipped: false) { rect in
            let lineWidth: CGFloat = 2.5
            let inset = lineWidth / 2 + 1
            let circle = rect.insetBy(dx: inset, dy: inset)
            let track = NSBezierPath(ovalIn: circle)
            track.lineWidth = lineWidth
            NSColor.labelColor.withAlphaComponent(0.16).setStroke()
            track.stroke()

            let p = max(0, min(1, progress))
            if p > 0.001 {
                let arc = NSBezierPath()
                let start: CGFloat = 90  // 12 点方向起笔
                arc.appendArc(withCenter: NSPoint(x: rect.midX, y: rect.midY),
                              radius: circle.width / 2,
                              startAngle: start,
                              endAngle: start - 360 * p,
                              clockwise: true)
                arc.lineWidth = lineWidth
                arc.lineCapStyle = .round
                color.setStroke()
                arc.stroke()
            }

            if let glyph {
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: glyphFont),
                    .foregroundColor: color
                ]
                let text = glyph as NSString
                let tsize = text.size(withAttributes: attrs)
                text.draw(at: NSPoint(x: rect.midX - tsize.width / 2,
                                      y: rect.midY - tsize.height / 2),
                          withAttributes: attrs)
            }
            return true
        }
        img.isTemplate = false
        return img
    }
}

/// 顶栏的胶囊按钮：自己画背景和文字，避免系统 bezel 在不同字号下把字顶偏
final class CapsuleButton: NSButton {
    var fillAlpha: CGFloat = 0.07

    init(title: String, action: Selector, tooltip: String) {
        super.init(frame: NSRect(x: 0, y: 0, width: 64, height: 26))
        self.title = title
        self.target = nil
        self.action = action
        self.isBordered = false
        self.focusRingType = .none
        self.toolTip = tooltip
        self.font = NSFont.systemFont(ofSize: 11.5, weight: .regular)
        self.setContentHuggingPriority(.required, for: .horizontal)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var intrinsicContentSize: NSSize {
        let w = (title as NSString).size(withAttributes: [.font: font ?? .systemFont(ofSize: 11.5)]).width
        return NSSize(width: ceil(w) + 20, height: 26)
    }

    override func draw(_ dirtyRect: NSRect) {
        let r = bounds.insetBy(dx: 0.5, dy: 0.5)
        let path = NSBezierPath(roundedRect: r, xRadius: 7, yRadius: 7)
        NSColor.labelColor.withAlphaComponent(isHighlighted ? fillAlpha + 0.09 : fillAlpha).setFill()
        path.fill()
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font ?? NSFont.systemFont(ofSize: 11.5),
            .foregroundColor: NSColor.labelColor
        ]
        let str = title as NSString
        let size = str.size(withAttributes: attrs)
        // 垂直居中：按字形高度自己算，而不是让 cell 去猜
        let y = (bounds.height - size.height) / 2 + 1
        str.draw(at: NSPoint(x: (bounds.width - size.width) / 2, y: y), withAttributes: attrs)
    }
}

/// 主窗口顶栏里的环按钮：点一下执行 action，图形由更新函数负责
final class RingButton: NSButton {
    var ringProgress: CGFloat = 0 { didSet { refreshImage() } }
    var ringColor: NSColor = .systemRed { didSet { refreshImage() } }
    var glyph: String? { didSet { refreshImage() } }
    var glyphFont: CGFloat = 9 { didSet { refreshImage() } }
    var idleGlyphFallback: String?
    var onHover: ((Bool) -> Void)?
    private var hoverTracking: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = hoverTracking { removeTrackingArea(t) }
        let t = NSTrackingArea(rect: bounds,
                               options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                               owner: self, userInfo: nil)
        addTrackingArea(t)
        hoverTracking = t
    }

    override func mouseEntered(with event: NSEvent) { onHover?(true) }
    override func mouseExited(with event: NSEvent) { onHover?(false) }

    init(action: Selector, tooltip: String) {
        super.init(frame: NSRect(x: 0, y: 0, width: 34, height: 28))
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: 34).isActive = true
        heightAnchor.constraint(equalToConstant: 28).isActive = true
        self.target = nil
        self.action = action
        self.isBordered = false
        self.bezelStyle = .regularSquare
        self.title = ""
        self.toolTip = tooltip
        self.imagePosition = .imageOnly
        self.setButtonType(.momentaryChange)
        refreshImage()
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    private func refreshImage() {
        // 空闲时灰环 + 淡符号，运行中彩色环
        let color = ringProgress > 0.001 ? ringColor : NSColor.secondaryLabelColor
        image = NSImage.ring(progress: ringProgress, color: color, size: 26,
                             glyph: glyph ?? idleGlyphFallback, glyphFont: glyphFont)
    }
}

extension EditorRoot {

    // MARK: 安装 / 刷新

    func installStatusItem() {
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.toolTip = "落笔 · 番茄钟与今日进度"
        statusItem = item
        rebuildStatusMenu()
        refreshStatusItem()
    }

    func refreshStatusItem() {
        guard let item = statusItem else { return }
        let goal = doc.dailyGoal
        let wrote = doc.todayWritten
        if hasPomoSession {
            let p = min(1, pomoElapsed / pomoDuration)
            let color: NSColor = pomoIsOvertime ? .systemOrange : (pomoIsBreak ? .systemBlue : .systemRed)
            item.button?.image = NSImage.ring(progress: CGFloat(p),
                                              color: color,
                                              size: 22, glyph: pomoIsOvertime ? "+" : (pomoIsBreak ? "☕" : "T"))
            item.button?.attributedTitle = NSAttributedString(string: "")
            // 菜单栏上直接显示剩余时间——不用点开就能看
            item.button?.attributedTitle = NSAttributedString(
                string: " " + pomoRemainingText,
                attributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)])
        } else {
            let p: CGFloat = goal > 0 ? CGFloat(min(1, Double(wrote) / Double(goal))) : 0
            item.button?.image = NSImage.ring(progress: p,
                                              color: goal > 0 && wrote >= goal ? .systemGreen : .systemBlue,
                                              size: 20, glyph: "今")
            item.button?.attributedTitle = goal > 0
                ? NSAttributedString(string: " \(wrote)/\(goal)",
                                     attributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 10.5, weight: .regular),
                                                  .foregroundColor: NSColor.secondaryLabelColor])
                : NSAttributedString(string: "")
        }
        let state: String
        if !hasPomoSession { state = "idle" }
        else if pomoIsBreak { state = pomoRunning ? "break-run" : "break-pause" }
        else if pomoIsOvertime { state = "overtime" }
        else { state = pomoRunning ? "focus-run" : "focus-pause" }
        if state != statusMenuState {
            statusMenuState = state
            rebuildStatusMenu()
        } else {
            updateStatusMenuDynamic()
        }
    }

    /// 每秒只改这几行的文字，不重建整个菜单（重建会把正打开的菜单打断）
    func updateStatusMenuDynamic() {
        if let it = statusPomoItem {
            if !hasPomoSession {
                it.title = "开始 \(doc.focusMinutes) 分钟专注"
            } else if pomoRunning {
                it.title = pomoIsOvertime ? "暂停（已超时 \(pomoOvertimeText)）" : "暂停（还剩 \(pomoRemainingText)）"
            } else {
                it.title = "继续（还剩 \(pomoRemainingText)）"
            }
        }
        statusGoalItem?.title = doc.dailyGoal > 0
            ? "今日：\(doc.todayWritten) / \(doc.dailyGoal) 字"
            : "今日：\(doc.todayWritten) 字（没设目标）"
        statusTimeItem?.title = "写作 \(doc.todaySeconds / 60) 分钟 · 番茄 \(doc.todayPomodoros) 个"
    }

    var pomoRemainingText: String {
        guard hasPomoSession else { return "未开始" }
        let secs = Int(pomoRemaining.rounded(.up))
        return String(format: "%02d:%02d", secs / 60, secs % 60)
    }

    /// 超时后的正计时，形如 "+03:20"
    var pomoOvertimeText: String {
        let secs = Int(pomoOvertime)
        return String(format: "+%02d:%02d", secs / 60, secs % 60)
    }

    // MARK: 菜单（系统栏里那一份）

    func rebuildStatusMenu() {
        guard let item = statusItem else { return }
        let menu = NSMenu()
        menu.autoenablesItems = false

        func add(_ title: String, _ sel: String?) {
            let it = NSMenuItem(title: title, action: sel.map { Selector($0) }, keyEquivalent: "")
            it.target = self
            menu.addItem(it)
        }

        // 番茄
        if !hasPomoSession {
            add("开始 \(doc.focusMinutes) 分钟专注", "startPomodoroFromMenu:")
        } else {
            add(pomoRunning ? "暂停（还剩 \(pomoRemainingText)）" : "继续（还剩 \(pomoRemainingText)）", "togglePomodoro:")
            add(pomoIsBreak ? "结束休息" : "提前休息", "skipToBreak:")
        }
        statusPomoItem = menu.items.first { $0.action != nil && $0.target === self }

        menu.addItem(.separator())
        let goalTitle = doc.dailyGoal > 0
            ? "今日：\(doc.todayWritten) / \(doc.dailyGoal) 字"
            : "今日：\(doc.todayWritten) 字（没设目标）"
        let goalItem = NSMenuItem(title: goalTitle, action: nil, keyEquivalent: "")
        goalItem.isEnabled = false
        menu.addItem(goalItem)
        statusGoalItem = goalItem
        let timeTitle = "写作 \(doc.todaySeconds / 60) 分钟 · 番茄 \(doc.todayPomodoros) 个"
        let timeItem = NSMenuItem(title: timeTitle, action: nil, keyEquivalent: "")
        timeItem.isEnabled = false
        menu.addItem(timeItem)
        statusTimeItem = timeItem

        menu.addItem(.separator())
        add("设置今日写作目标…", "showGoalPanel:")
        add("写作统计…", "showStatsPanel:")
        add("今天（今日页）…", "showTodayPanel:")
        let shadowItem = NSMenuItem(title: shadowModeEnabled ? "影子模式：开" : "影子模式：关",
                                    action: Selector(("toggleShadowMode:")), keyEquivalent: "")
        shadowItem.target = self
        shadowItem.state = shadowModeEnabled ? .on : .off
        menu.addItem(shadowItem)
        add("大纲板…", "showBoard:")
        add("人物一览…", "showCardsOverview:")
        menu.addItem(.separator())
        add("番茄钟时长设置…", "showPomodoroSettings:")
        add("显示主窗口", "bringWindowToFront:")
        add("外观与字号…", "showThemePanel:")
        add("功能说明与使用指南…", "showGuide:")
        menu.addItem(.separator())
        add("退出 落笔", "terminate:")
        item.menu = menu
    }

    @objc func skipToBreak(_ sender: Any?) {
        if pomoIsBreak {
            closePomodoro()
        } else {
            closePomodoro()
            startPomodoro(isBreak: true)
        }
        refreshStatusItem()
    }

    @objc func bringWindowToFront(_ sender: Any?) {
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
