import AppKit

// MARK: - 设置（只放"看得见多少"的开关，不塞写作功能）
//
// 设计取舍：数据一直在记（速率、效率、影子都要历史才有意义），
// 但"要不要看见"是使用者的事——所以这里不做开关数据采集，只做开关展示。

extension EditorRoot {

    @objc func showSettingsPanel(_ sender: Any?) {
        let preset = ThemePresets.preset(doc.theme)
        let panel = LuobiSheetPanel(contentRect: NSRect(x: 0, y: 0, width: 520, height: 400),
                                   styleMask: [.titled],
                                   backing: .buffered, defer: false)
        panel.title = "设置"
        panel.isReleasedWhenClosed = false
        if preset.isDark { panel.appearance = NSAppearance(named: .darkAqua) }

        let body = NSView()
        body.wantsLayer = true
        body.layer?.backgroundColor = preset.bg.cgColor

        let title = NSTextField(labelWithString: "显示与提醒")
        title.font = Typo.bold(20)
        title.textColor = preset.text
        title.translatesAutoresizingMaskIntoConstraints = false
        body.addSubview(title)

        let sub = NSTextField(labelWithString: "这些都只影响「你能看到什么」，一天的字数、番茄、影子数据一直都在记。")
        sub.font = NSFont.systemFont(ofSize: 12)
        sub.textColor = preset.text.withAlphaComponent(0.6)
        sub.maximumNumberOfLines = 0
        sub.translatesAutoresizingMaskIntoConstraints = false
        body.addSubview(sub)

        let rows = NSStackView()
        rows.orientation = .vertical
        rows.alignment = .leading
        rows.spacing = 14
        rows.translatesAutoresizingMaskIntoConstraints = false
        body.addSubview(rows)

        let date = NSTextField(labelWithString: "")
        let time = NSTextField(labelWithString: "")
        _ = date; _ = time

        rows.addArrangedSubview(makeToggleRow(
            preset: preset,
            title: "写作速率",
            detail: "今日浮层里显示「平均多少字/分钟、最快多少」",
            on: doc.showSpeed,
            key: "showSpeed"))
        rows.addArrangedSubview(makeToggleRow(
            preset: preset,
            title: "产出效率",
            detail: "每个番茄写了多少字、比近 7 天高还是低",
            on: doc.showEffect,
            key: "showEffect"))
        rows.addArrangedSubview(makeToggleRow(
            preset: preset,
            title: "影子模式",
            detail: "拿过去几天同一时刻的产量做参照，只显示一行对比，不催你",
            on: doc.shadowMode,
            key: "shadowMode"))
        rows.addArrangedSubview(makeToggleRow(
            preset: preset,
            title: "番茄钟",
            detail: "关闭后顶栏的 🍅 环和菜单栏倒计时都会消失，写作计时照旧",
            on: doc.pomodoroEnabled,
            key: "pomodoroEnabled"))

        body.addSubview(title)
        NSLayoutConstraint.activate([
            title.leadingAnchor.constraint(equalTo: body.leadingAnchor, constant: 28),
            title.topAnchor.constraint(equalTo: body.topAnchor, constant: 26),
            sub.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            sub.trailingAnchor.constraint(equalTo: body.trailingAnchor, constant: -28),
            sub.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 8),
            rows.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            rows.trailingAnchor.constraint(equalTo: body.trailingAnchor, constant: -28),
            rows.topAnchor.constraint(equalTo: sub.bottomAnchor, constant: 22)
        ])

        body.translatesAutoresizingMaskIntoConstraints = false
        let wrap = wrapWithFooter(body, footerTitle: "完成")
        panel.contentView = wrap
        panel.onEsc = { [weak panel] in panel?.closeSelf() }
        presentSheet(panel)
    }

    /// 一行开关：标题 + 说明 + NSSwitch。用 tag 记字段名，避免一组闭包互相捕获。
    private func makeToggleRow(preset: ThemePreset, title: String, detail: String,
                               on: Bool, key: String) -> NSView {
        let row = NSView()
        row.translatesAutoresizingMaskIntoConstraints = false

        let name = NSTextField(labelWithString: title)
        name.font = Typo.bold(13)
        name.textColor = preset.text
        name.translatesAutoresizingMaskIntoConstraints = false

        let note = NSTextField(labelWithString: detail)
        note.font = NSFont.systemFont(ofSize: 11.5)
        note.textColor = preset.text.withAlphaComponent(0.55)
        note.maximumNumberOfLines = 0
        note.translatesAutoresizingMaskIntoConstraints = false

        let toggle = NSSwitch()
        toggle.state = on ? .on : .off
        toggle.controlSize = .small
        toggle.translatesAutoresizingMaskIntoConstraints = false
        toggle.target = self
        toggle.action = Selector(("settingsToggleChanged:"))
        toggle.identifier = NSUserInterfaceItemIdentifier(key)

        row.addSubview(name)
        row.addSubview(note)
        row.addSubview(toggle)
        NSLayoutConstraint.activate([
            row.heightAnchor.constraint(equalToConstant: 46),
            name.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            name.topAnchor.constraint(equalTo: row.topAnchor),
            note.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            note.topAnchor.constraint(equalTo: name.bottomAnchor, constant: 2),
            note.trailingAnchor.constraint(lessThanOrEqualTo: toggle.leadingAnchor, constant: -16),
            toggle.trailingAnchor.constraint(equalTo: row.trailingAnchor),
            toggle.centerYAnchor.constraint(equalTo: row.centerYAnchor)
        ])
        return row
    }

    @objc func settingsToggleChanged(_ sender: NSSwitch) {
        let key = sender.identifier?.rawValue ?? ""
        let on = sender.state == .on
        switch key {
        case "showSpeed": doc.showSpeed = on
        case "showEffect": doc.showEffect = on
        case "shadowMode": doc.shadowMode = on
        case "pomodoroEnabled": doc.pomodoroEnabled = on
        default: break
        }
        persistNow()
        applyPomodoroVisibility()
        rebuildStatusMenu()
        refreshBar()
    }
}
