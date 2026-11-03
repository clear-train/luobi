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

/// 主窗口顶栏里的环按钮：点一下执行 action，图形由更新函数负责
final class RingButton: NSButton {
    var ringProgress: CGFloat = 0 { didSet { refreshImage() } }
    var ringColor: NSColor = .systemRed { didSet { refreshImage() } }
    var glyph: String? { didSet { refreshImage() } }
    var idleGlyphFallback: String?

    init(action: Selector, tooltip: String) {
        super.init(frame: NSRect(x: 0, y: 0, width: 28, height: 24))
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
        image = NSImage.ring(progress: ringProgress, color: color, size: 20,
                             glyph: glyph ?? idleGlyphFallback)
    }
}

extension EditorRoot {

    // MARK: 安装 / 刷新

    func installStatusItem() {
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.toolTip = "Ulysses Native · 番茄钟与今日进度"
        statusItem = item
        rebuildStatusMenu()
        refreshStatusItem()
    }

    func refreshStatusItem() {
        guard let item = statusItem else { return }
        let goal = doc.dailyGoal
        let wrote = doc.todayWritten
        if let end = pomoEndAt {
            let total = pomoIsBreak ? 300.0 : 1500.0
            let left = max(0, end.timeIntervalSinceNow)
            let p = 1 - left / total
            item.button?.image = NSImage.ring(progress: CGFloat(p),
                                              color: pomoIsBreak ? .systemBlue : .systemRed,
                                              size: 20, glyph: pomoIsBreak ? "☕" : "番")
            item.button?.attributedTitle = NSAttributedString(string: "")
        } else {
            let p: CGFloat = goal > 0 ? CGFloat(min(1, Double(wrote) / Double(goal))) : 0
            item.button?.image = NSImage.ring(progress: p,
                                              color: goal > 0 && wrote >= goal ? .systemGreen : .systemBlue,
                                              size: 20, glyph: "今")
            item.button?.attributedTitle = NSAttributedString(string: "")
        }
        rebuildStatusMenu()
    }

    var pomoRemainingText: String {
        guard let end = pomoEndAt else { return "未开始" }
        let left = max(0, Int(end.timeIntervalSinceNow.rounded(.up)))
        return String(format: "%02d:%02d", left / 60, left % 60)
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
        if pomoEndAt == nil {
            add("开始 25 分钟专注", "startPomodoroFromMenu:")
        } else {
            add("暂停（还剩 \(pomoRemainingText)）", "togglePomodoro:")
            add(pomoIsBreak ? "跳过休息" : "提前休息", "skipToBreak:")
        }

        menu.addItem(.separator())
        let goalTitle = doc.dailyGoal > 0
            ? "今日：\(doc.todayWritten) / \(doc.dailyGoal) 字"
            : "今日：\(doc.todayWritten) 字（没设目标）"
        let goalItem = NSMenuItem(title: goalTitle, action: nil, keyEquivalent: "")
        goalItem.isEnabled = false
        menu.addItem(goalItem)
        let timeTitle = "写作 \(doc.todaySeconds / 60) 分钟 · 番茄 \(doc.todayPomodoros) 个"
        let timeItem = NSMenuItem(title: timeTitle, action: nil, keyEquivalent: "")
        timeItem.isEnabled = false
        menu.addItem(timeItem)

        menu.addItem(.separator())
        add("设置今日写作目标…", "showGoalPanel:")
        add("写作统计…", "showStatsPanel:")
        add("大纲板…", "showBoard:")
        add("人物一览…", "showCardsOverview:")
        menu.addItem(.separator())
        add("显示主窗口", "bringWindowToFront:")
        add("外观与字号…", "showThemePanel:")
        add("功能说明与使用指南…", "showGuide:")
        menu.addItem(.separator())
        add("退出 Ulysses Native", "terminate:")
        item.menu = menu
    }

    @objc func startPomodoroFromMenu(_ sender: Any?) {
        startPomodoro(isBreak: false)
    }

    @objc func skipToBreak(_ sender: Any?) {
        if pomoIsBreak {
            closePomodoro()
        } else {
            pausePomodoro()
            startPomodoro(isBreak: true)
        }
        refreshStatusItem()
    }

    @objc func bringWindowToFront(_ sender: Any?) {
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
