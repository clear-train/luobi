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
        if let old = win.attachedSheet { win.endSheet(old) }
        win.beginSheet(panel) { _ in }
    }

    /// 面板内容 = 主体 + 底栏（主体自己撑满剩余空间）
    func wrapWithFooter(_ body: NSView, footerTitle: String = "完成") -> NSView {
        let wrap = NSView()
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
