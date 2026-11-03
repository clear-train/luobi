import AppKit

// MARK: - 「外观」面板：4 套主题即时切换 + 正文字号滑块
//
// 触发：顶部工具栏 / 视图菜单 → `showThemePanel:`
// 展示：有主窗口时用 beginSheet 挂成 sheet；没有窗口（异常/测试路径）退化为 runModal。
// 交互：点色块立刻改主题并落盘、不关面板（可以边点边看效果）；
//      拖字号滑块立刻改 doc.fontSize、重排并落盘；「完成」或 Esc 关闭。

final class ThemePanelWindow: NSPanel {

    weak var hostWindow: NSWindow?
    private weak var editor: EditorRoot?

    private let rootStack = NSStackView()
    private var swatches: [NSButton] = []
    private var swatchLabels: [NSTextField] = []
    private let sizeLabel = NSTextField(labelWithString: "17 pt")
    private let sizeSlider = NSSlider()
    private let leadLabel = NSTextField(labelWithString: "10")
    private let leadSlider = NSSlider()
    private let paraLabel = NSTextField(labelWithString: "10")
    private let paraSlider = NSSlider()
    private let indentLabel = NSTextField(labelWithString: "2 字")
    private let indentSlider = NSSlider()

    private static let swatchSide: CGFloat = 44
    private static let contentWidth: CGFloat = 420
    private static let contentHeight: CGFloat = 380
    private static let sideInset: CGFloat = 20

    // MARK: 初始化

    init(editor: EditorRoot) {
        super.init(contentRect: NSRect(x: 0, y: 0,
                                       width: Self.contentWidth,
                                       height: Self.contentHeight),
                   styleMask: [.titled],
                   backing: .buffered,
                   defer: false)
        self.editor = editor
        title = "外观"
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        buildContent()
        syncAppearance()
        center()
    }

    required init?(coder: NSCoder) { fatalError("不走 storyboard") }

    // MARK: 关闭

    @objc func dismissPanel(_ sender: Any?) {
        if let host = hostWindow, host.attachedSheet === self {
            host.endSheet(self)
            return
        }
        if NSApp.modalWindow === self {
            NSApp.stopModal()
            orderOut(nil)
            return
        }
        close()
    }

    /// Esc 等同「完成」
    override func cancelOperation(_ sender: Any?) {
        dismissPanel(sender)
    }

    // MARK: 外观跟随当前主题

    /// 面板自身 appearance 跟随当前主题（深夜 → darkAqua），并刷新色块选中边框。
    func syncAppearance() {
        let preset = ThemePresets.preset(editor?.doc.theme ?? "paper")
        appearance = NSAppearance(named: preset.isDark ? .darkAqua : .aqua)
        contentView?.layer?.backgroundColor = preset.bg.cgColor
        refreshSelection()
    }

    // MARK: 交互

    @objc private func pickTheme(_ sender: NSButton) {
        guard let editor = editor, ThemePresets.all.indices.contains(sender.tag) else { return }
        let preset = ThemePresets.all[sender.tag]

        editor.doc.theme = preset.id
        editor.applyTheme(nil)
        editor.persistNow()

        // 不关面板：就地更新高亮与面板明暗，用户可以一套套点着看
        syncAppearance()
    }

    @objc private func leadChanged(_ sender: NSSlider) {
        guard let editor = editor else { return }
        let v = sender.doubleValue.rounded()
        sender.doubleValue = v
        leadLabel.stringValue = "\(Int(v))"
        editor.doc.lineSpacing = v
        editor.persistNow()
        editor.requestStylesRefresh()
    }

    @objc private func paraChanged(_ sender: NSSlider) {
        guard let editor = editor else { return }
        let v = sender.doubleValue.rounded()
        sender.doubleValue = v
        paraLabel.stringValue = "\(Int(v))"
        editor.doc.paragraphSpacing = v
        editor.persistNow()
        editor.requestStylesRefresh()
    }

    @objc private func indentChanged(_ sender: NSSlider) {
        guard let editor = editor else { return }
        let v = Int(sender.doubleValue.rounded())
        sender.doubleValue = Double(v)
        indentLabel.stringValue = v == 0 ? "不缩进" : "\(v) 字"
        editor.doc.indentChars = v
        editor.persistNow()
        editor.requestStylesRefresh()
    }

    @objc private func sizeChanged(_ sender: NSSlider) {
        guard let editor = editor else { return }
        let value = min(20, max(15, sender.doubleValue.rounded()))
        sender.doubleValue = value
        sizeLabel.stringValue = "\(Int(value)) pt"

        editor.doc.fontSize = value
        editor.persistNow()
        editor.requestStylesRefresh()
    }

    // MARK: 构建界面

    private func buildContent() {
        guard let content = contentView else { return }
        let inset = Self.sideInset
        // 面板底色跟随主题，否则羊皮纸界面里突然弹一块纯白，很刺眼
        content.wantsLayer = true
        content.layer?.backgroundColor = ThemePresets.preset(editor?.doc.theme ?? "paper").bg.cgColor

        // 上半部分：主题 + 字号 + 说明（自上而下排布）
        rootStack.orientation = .vertical
        rootStack.alignment = .leading
        rootStack.distribution = .fill
        rootStack.spacing = 12
        rootStack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(rootStack)

        // 底部：弹性留白 + 「完成」
        let footer = makeFooter()
        content.addSubview(footer)   // 必须先入树，下面才可以用它的 anchor 加约束

        NSLayoutConstraint.activate([
            rootStack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: inset),
            rootStack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -inset),
            rootStack.topAnchor.constraint(equalTo: content.topAnchor, constant: inset),

            footer.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: inset),
            footer.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -inset),
            footer.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -inset),
            footer.topAnchor.constraint(greaterThanOrEqualTo: rootStack.bottomAnchor, constant: 12),
        ])

        rootStack.addArrangedSubview(makeSectionLabel("主题"))
        let swatchRow = makeSwatchRow()
        rootStack.addArrangedSubview(swatchRow)

        let sizeRow = makeSizeRow()
        rootStack.addArrangedSubview(sizeRow)
        // 字号行占满内容宽度，滑块吃掉多余空间
        sizeRow.widthAnchor.constraint(equalTo: rootStack.widthAnchor).isActive = true

        for row in [makeLeadRow(), makeParaRow(), makeIndentRow()] {
            rootStack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: rootStack.widthAnchor).isActive = true
        }

        let note = makeNote()
        rootStack.addArrangedSubview(note)
        note.preferredMaxLayoutWidth = Self.contentWidth - inset * 2
        note.widthAnchor.constraint(equalTo: rootStack.widthAnchor).isActive = true

        configFontSize()
        configSpacing()
    }

    private func makeSectionLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 11, weight: .semibold)
        label.textColor = .secondaryLabelColor
        return label
    }

    /// 4 个 44×44 色块，下面一行 11pt 名字
    private func makeSwatchRow() -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .top
        row.spacing = 12
        row.translatesAutoresizingMaskIntoConstraints = false

        for (index, preset) in ThemePresets.all.enumerated() {
            let item = NSStackView()
            item.orientation = .vertical
            item.alignment = .centerX
            item.spacing = 6
            item.translatesAutoresizingMaskIntoConstraints = false

            let swatch = NSButton(title: "", target: self, action: #selector(pickTheme(_:)))
            swatch.tag = index
            swatch.bezelStyle = .shadowlessSquare
            swatch.isBordered = false          // 只用 layer 画色块，别让系统 bezel 盖住颜色
            swatch.focusRingType = .none
            swatch.wantsLayer = true
            swatch.layer?.backgroundColor = preset.bg.cgColor
            swatch.layer?.cornerRadius = 8
            swatch.layer?.borderWidth = 2
            swatch.layer?.masksToBounds = true
            swatch.toolTip = preset.name
            swatch.setAccessibilityLabel(preset.name)
            swatch.translatesAutoresizingMaskIntoConstraints = false
            swatch.widthAnchor.constraint(equalToConstant: Self.swatchSide).isActive = true
            swatch.heightAnchor.constraint(equalToConstant: Self.swatchSide).isActive = true
            swatches.append(swatch)

            let name = NSTextField(labelWithString: preset.name)
            name.font = .systemFont(ofSize: 11)
            name.textColor = .secondaryLabelColor
            name.alignment = .center
            name.translatesAutoresizingMaskIntoConstraints = false
            swatchLabels.append(name)

            item.addArrangedSubview(swatch)
            item.addArrangedSubview(name)
            row.addArrangedSubview(item)
        }
        return row
    }

    /// 「正文字号」+ 滑块（15…20，6 档）+ 右侧「17 pt」
    private func makeSizeRow() -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 10
        row.translatesAutoresizingMaskIntoConstraints = false

        let caption = NSTextField(labelWithString: "正文字号")
        caption.font = .systemFont(ofSize: 13)
        caption.setContentHuggingPriority(.required, for: .horizontal)

        sizeSlider.minValue = 15
        sizeSlider.maxValue = 20
        sizeSlider.numberOfTickMarks = 6
        sizeSlider.allowsTickMarkValuesOnly = true
        sizeSlider.isContinuous = true
        sizeSlider.controlSize = .small
        sizeSlider.target = self
        sizeSlider.action = #selector(sizeChanged(_:))
        sizeSlider.setContentHuggingPriority(.defaultLow, for: .horizontal)
        sizeSlider.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        sizeSlider.translatesAutoresizingMaskIntoConstraints = false

        sizeLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        sizeLabel.textColor = .secondaryLabelColor
        sizeLabel.alignment = .right
        sizeLabel.translatesAutoresizingMaskIntoConstraints = false
        sizeLabel.widthAnchor.constraint(equalToConstant: 46).isActive = true

        row.addArrangedSubview(caption)
        row.addArrangedSubview(sizeSlider)
        row.addArrangedSubview(sizeLabel)
        return row
    }

    /// 通用：标题 + 滑块 + 右侧数值
    private func makeSliderRow(_ caption: String,
                               slider: NSSlider,
                               label: NSTextField,
                               min: Double,
                               max: Double,
                               ticks: Int,
                               action: Selector) -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 10

        let cap = NSTextField(labelWithString: caption)
        cap.font = .systemFont(ofSize: 13)
        cap.setContentHuggingPriority(.required, for: .horizontal)
        cap.widthAnchor.constraint(equalToConstant: 56).isActive = true

        slider.minValue = min
        slider.maxValue = max
        slider.numberOfTickMarks = ticks
        slider.allowsTickMarkValuesOnly = true
        slider.isContinuous = true
        slider.controlSize = .small
        slider.target = self
        slider.action = action
        slider.setContentHuggingPriority(.defaultLow, for: .horizontal)

        label.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        label.textColor = .secondaryLabelColor
        label.alignment = .right
        label.widthAnchor.constraint(equalToConstant: 46).isActive = true

        row.addArrangedSubview(cap)
        row.addArrangedSubview(slider)
        row.addArrangedSubview(label)
        return row
    }

    private func makeLeadRow() -> NSView {
        makeSliderRow("行间距", slider: leadSlider, label: leadLabel,
                      min: 0, max: 24, ticks: 13, action: #selector(leadChanged(_:)))
    }

    private func makeParaRow() -> NSView {
        makeSliderRow("段间距", slider: paraSlider, label: paraLabel,
                      min: 0, max: 24, ticks: 13, action: #selector(paraChanged(_:)))
    }

    private func makeIndentRow() -> NSView {
        makeSliderRow("首行缩进", slider: indentSlider, label: indentLabel,
                      min: 0, max: 4, ticks: 5, action: #selector(indentChanged(_:)))
    }

    private func configSpacing() {
        guard let doc = editor?.doc else { return }
        let lead = min(24, max(0, doc.lineSpacing.rounded()))
        leadSlider.doubleValue = lead
        leadLabel.stringValue = "\(Int(lead))"
        let para = min(24, max(0, doc.paragraphSpacing.rounded()))
        paraSlider.doubleValue = para
        paraLabel.stringValue = "\(Int(para))"
        let ind = min(4, max(0, doc.indentChars))
        indentSlider.doubleValue = Double(ind)
        indentLabel.stringValue = ind == 0 ? "不缩进" : "\(ind) 字"
    }

    private func makeNote() -> NSTextField {
        let note = NSTextField(wrappingLabelWithString: "主题、字号、行距、缩进都会自动保存。行距调大一点更像书，不像记事本。")
        note.font = .systemFont(ofSize: 11)
        note.textColor = .secondaryLabelColor
        note.translatesAutoresizingMaskIntoConstraints = false
        return note
    }

    private func makeFooter() -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 10
        row.translatesAutoresizingMaskIntoConstraints = false

        let spacer = NSView()
        spacer.setContentHuggingPriority(.init(1), for: .horizontal)
        spacer.setContentCompressionResistancePriority(.init(1), for: .horizontal)

        let done = NSButton(title: "完成", target: self, action: #selector(dismissPanel(_:)))
        done.bezelStyle = .rounded
        done.keyEquivalent = "\r"
        done.translatesAutoresizingMaskIntoConstraints = false

        row.addArrangedSubview(spacer)
        row.addArrangedSubview(done)
        return row
    }

    private func configFontSize() {
        let value = min(20, max(15, (editor?.doc.fontSize ?? 17).rounded()))
        sizeSlider.doubleValue = value
        sizeLabel.stringValue = "\(Int(value)) pt"
    }

    /// 选中项：controlAccentColor 边框；其余：separatorColor。
    private func refreshSelection() {
        let current = ThemePresets.preset(editor?.doc.theme ?? "paper").id
        for (index, swatch) in swatches.enumerated() {
            let selected = ThemePresets.all[index].id == current
            swatch.state = selected ? .on : .off
            let color = selected ? NSColor.controlAccentColor : NSColor.separatorColor
            swatch.layer?.borderWidth = 2
            swatch.layer?.borderColor = resolved(color, in: swatch).cgColor
        }
    }

    /// 动态色（accent / separator）按面板当前 appearance 解析成 sRGB 具体色，
    /// 否则 layer 可能拿到浅色外观下的旧值。
    private func resolved(_ color: NSColor, in view: NSView) -> NSColor {
        var out = NSColor.gray
        view.effectiveAppearance.performAsCurrentDrawingAppearance {
            out = color.usingColorSpace(.sRGB) ?? NSColor.gray
        }
        return out
    }
}

// MARK: - 入口

extension EditorRoot {

    /// 顶部工具栏 / 菜单「主题」入口：打开「外观」面板
    @objc func showThemePanel(_ sender: Any?) {
        // 已经开着就不再叠一层
        if let host = window, let sheet = host.attachedSheet as? ThemePanelWindow {
            sheet.makeKeyAndOrderFront(nil)
            return
        }

        let panel = ThemePanelWindow(editor: self)
        panel.hostWindow = window

        if let host = window {
            host.beginSheet(panel, completionHandler: nil)
        } else {
            // 没有主窗口时兜底成模态面板（NSPanel 自身没有 runModal，走 NSApp）
            _ = NSApp.runModal(for: panel)
        }
    }
}
