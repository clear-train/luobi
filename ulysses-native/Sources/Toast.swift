import AppKit

// MARK: - 软提示（toast）
//
// 用户反馈：番茄钟弹窗「太硬」「占用精力」。
// 所以改成：右下角浮出一个小卡片，12 秒后自己消失，不抢焦点、不挡正文，
// 想休息就点「休息 5 分钟」，不想理会就继续写——不点等于默认「继续写」，这是有意的。

/// 不需要先点一下"激活"面板才能按到按钮
final class FirstMouseButton: NSButton {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

final class ToastPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// 卡片内容视图：自己画圆角底 + 标题 + 说明 + 按钮
final class ToastView: NSView {
    let titleLabel = NSTextField(labelWithString: "")
    let detailLabel = NSTextField(labelWithString: "")
    let buttonRow = NSStackView()
    var bgColor: NSColor = .windowBackgroundColor

    override var isFlipped: Bool { true }

    init(width: CGFloat) {
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: 96))
        wantsLayer = true

        titleLabel.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        titleLabel.frame = NSRect(x: 16, y: 14, width: width - 32, height: 18)
        addSubview(titleLabel)

        detailLabel.font = NSFont.systemFont(ofSize: 11.5)
        detailLabel.textColor = .secondaryLabelColor
        detailLabel.lineBreakMode = .byWordWrapping
        detailLabel.maximumNumberOfLines = 2
        detailLabel.frame = NSRect(x: 16, y: 34, width: width - 32, height: 32)
        addSubview(detailLabel)

        buttonRow.orientation = .horizontal
        buttonRow.spacing = 8
        buttonRow.frame = NSRect(x: width - 220, y: 66, width: 204, height: 22)
        addSubview(buttonRow)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 12, yRadius: 12)
        bgColor.setFill()
        path.fill()
        NSColor.separatorColor.withAlphaComponent(0.6).setStroke()
        path.lineWidth = 1
        path.stroke()
    }
}

extension EditorRoot {

    func dismissToast() {
        toastTimer?.invalidate()
        toastTimer = nil
        toastPanel?.orderOut(nil)
        toastPanel = nil
    }

    /// 软提示：右下角卡片，12 秒自动消失；buttons 里第一个是默认动作
    func showToast(title: String,
                   detail: String = "",
                   seconds: TimeInterval = 12,
                   buttons: [(String, Selector)] = []) {
        dismissToast()

        let preset = ThemePresets.preset(doc.theme)
        let width: CGFloat = 340
        let height: CGFloat = buttons.isEmpty ? 74 : 96
        let panel = ToastPanel(contentRect: NSRect(x: 0, y: 0, width: width, height: height),
                               styleMask: [.borderless, .nonactivatingPanel],
                               backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false

        let view = ToastView(width: width)
        view.frame = NSRect(x: 0, y: 0, width: width, height: height)
        view.bgColor = preset.bg
        view.titleLabel.stringValue = title
        view.titleLabel.textColor = preset.text
        view.detailLabel.stringValue = detail
        view.detailLabel.textColor = preset.text.withAlphaComponent(0.62)
        view.detailLabel.isHidden = detail.isEmpty
        panel.contentView = view

        for (i, spec) in buttons.enumerated() {
            let b = FirstMouseButton(title: spec.0, target: self, action: spec.1)
            b.bezelStyle = .rounded
            b.controlSize = .small
            b.font = NSFont.systemFont(ofSize: 11)
            if i == 0 { b.keyEquivalent = "\r" }
            view.buttonRow.addArrangedSubview(b)
        }
        if buttons.isEmpty {
            let close = FirstMouseButton(title: "知道了", target: self, action: Selector(("dismissToast:")))
            close.bezelStyle = .rounded
            close.controlSize = .small
            close.font = NSFont.systemFont(ofSize: 11)
            view.buttonRow.addArrangedSubview(close)
        }

        // 贴在主窗口右下角（不在窗口外面乱飘）
        if let w = window {
            let x = w.frame.maxX - width - 24
            let y = w.frame.minY + 84
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        } else {
            panel.center()
        }
        panel.orderFrontRegardless()
        toastPanel = panel
        toastTimer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { [weak self] _ in
            self?.dismissToast()
        }
    }

    @objc func dismissToast(_ sender: Any?) {
        dismissToast()
    }
}
