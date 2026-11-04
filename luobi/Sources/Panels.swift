import AppKit

/// 所有 sheet 面板的统一底座。
///
/// 之前的教训：面板做出来后只有"点内容"才能关，一旦内容为空（比如还没有人物卡时
/// 打开人物一览），sheet 就卡在那里，Esc 也退不掉。所以把 Esc 和"结束 sheet"
/// 做成面板自身的能力，而不是每个面板各写一遍。
final class LuobiSheetPanel: NSPanel {
    var onEsc: (() -> Void)?

    override func cancelOperation(_ sender: Any?) { escape() }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.keyCode == 53 { escape(); return true }
        return super.performKeyEquivalent(with: event)
    }

    private func escape() {
        if let h = onEsc { h() } else { closeSelf() }
    }

    /// sheet 必须用 endSheet 结束；对 sheet 调 close() 有时只是隐藏，看起来像"没反应"
    func closeSelf() {
        if let parent = sheetParent {
            parent.endSheet(self)
        } else {
            close()
        }
    }
}

extension EditorRoot {

    /// 面板底栏：一根细分隔线 + 右下角「完成」。
    /// 每个 sheet 都必须有它——这是"一定能退出"的保证。
    func makePanelFooter(title: String = "完成") -> NSView {
        let bar = NSView()
        bar.translatesAutoresizingMaskIntoConstraints = false
        let line = NSBox()
        line.boxType = .separator
        line.translatesAutoresizingMaskIntoConstraints = false
        let btn = CapsuleButton(title: title,
                                action: Selector(("dismissSheetPanel:")),
                                tooltip: "关闭这个面板（按 Esc 也可以）")
        btn.target = self
        btn.translatesAutoresizingMaskIntoConstraints = false
        bar.addSubview(line)
        bar.addSubview(btn)
        NSLayoutConstraint.activate([
            line.leadingAnchor.constraint(equalTo: bar.leadingAnchor, constant: 0),
            line.trailingAnchor.constraint(equalTo: bar.trailingAnchor, constant: 0),
            line.topAnchor.constraint(equalTo: bar.topAnchor),
            line.heightAnchor.constraint(equalToConstant: 1),
            btn.trailingAnchor.constraint(equalTo: bar.trailingAnchor, constant: -14),
            btn.centerYAnchor.constraint(equalTo: bar.centerYAnchor, constant: 1),
            btn.heightAnchor.constraint(equalToConstant: 24),
            bar.heightAnchor.constraint(equalToConstant: 44),
        ])
        return bar
    }

    /// 统一的弹出方式：永远只有一个 sheet。
    /// 之前的坑：上一个 sheet 还挂着时再点另一个面板，beginSheet 会静默失败。
    func presentSheet(_ panel: NSWindow) {
        guard let win = window else {
            panel.makeKeyAndOrderFront(nil)
            return
        }
        // 换面板的坑：上一个 sheet 还没走完就 beginSheet，会被静默忽略，
        // 表现就是「点了没反应，得再点一次」。所以先结束旧的，下一轮再开新的。
        // sheet 呈现时 AppKit 会按 contentView 的"最小合理解"重设窗口尺寸，
        // 逐帧排版的面板会被压成 1pt 宽（实测），所以呈现后把尺寸钉回去。
        let target = NSSize(width: panel.contentView?.frame.width ?? panel.frame.width,
                            height: (panel.contentView?.frame.height ?? panel.frame.height) + 32)
        if let old = win.attachedSheet {
            win.endSheet(old)
            DispatchQueue.main.async {
                win.makeKey()
                win.beginSheet(panel) { _ in win.makeKey() }
                panel.setContentSize(target)
            }
        } else {
            win.beginSheet(panel) { _ in win.makeKey() }
            DispatchQueue.main.async { panel.setContentSize(target) }
        }
    }

    /// 面板内容 = 主体 + 底栏（主体自己撑满剩余空间）
    func wrapWithFooter(_ body: NSView, footerTitle: String = "完成") -> NSView {
        // 注意：这里不能给 wrap 用纯 Auto Layout。wrap 一旦作为 contentView，
        // 没有内在尺寸就会把窗口压成 1pt 宽（实测过：面板出来只有一条线）。
        // 所以 wrap 用固定 frame + autoresizing，body 在里面再用约束撑开。
        let wrapSize = NSSize(width: max(200, body.frame.width),
                              height: max(120, body.frame.height) + 44)
        let wrap = NSView(frame: NSRect(origin: .zero, size: wrapSize))
        wrap.autoresizingMask = []
        // 显式钉死宽高：sheet 呈现时 AppKit 会按 fittingSize 决定窗口尺寸，
        // 只靠相对约束的容器会被算成 1pt 宽（面板变成一条竖线）。
        wrap.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            wrap.widthAnchor.constraint(equalToConstant: wrapSize.width),
            wrap.heightAnchor.constraint(equalToConstant: wrapSize.height)
        ])
        wrap.wantsLayer = true
        wrap.layer?.backgroundColor = ThemePresets.preset(doc.theme).bg.cgColor
        let footer = makePanelFooter(title: footerTitle)
        body.translatesAutoresizingMaskIntoConstraints = false
        wrap.addSubview(body)
        wrap.addSubview(footer)
        NSLayoutConstraint.activate([
            body.topAnchor.constraint(equalTo: wrap.topAnchor),
            body.leadingAnchor.constraint(equalTo: wrap.leadingAnchor),
            body.trailingAnchor.constraint(equalTo: wrap.trailingAnchor),
            body.bottomAnchor.constraint(equalTo: footer.topAnchor),
            footer.leadingAnchor.constraint(equalTo: wrap.leadingAnchor),
            footer.trailingAnchor.constraint(equalTo: wrap.trailingAnchor),
            footer.bottomAnchor.constraint(equalTo: wrap.bottomAnchor),
        ])
        return wrap
    }
}
