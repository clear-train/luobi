import AppKit

// MARK: - 主题模块：4 套预设（羊皮纸 / 米白 / 护眼绿 / 深夜）
//
// 职责边界：这里只负责「颜色观感」——窗口外观、各级背景色、正文前景色与光标色。
// 字号、行距、Markdown 结构归 Typography + Styling 管；切主题时绝不重建 textView，
// 只改颜色，必要时请排版模块重排一次（reapplyStyles），排版结果原样保留。

// MARK: - 预设

struct ThemePreset {
    let id: String        // paper / ivory / green / deep
    let name: String      // 显示名
    let bg: NSColor       // 窗口 / 编辑区底色
    let text: NSColor     // 正文色
    let isDark: Bool      // 是否深色主题（决定 .darkAqua / .aqua）
}

enum ThemePresets {

    /// 4 套预设；数组顺序即 toggleTheme 的循环顺序
    static let all: [ThemePreset] = [
        ThemePreset(id: "paper", name: "羊皮纸", bg: rgb(0xF6F2E7), text: rgb(0x2B2620), isDark: false),
        ThemePreset(id: "ivory", name: "米白",   bg: rgb(0xFCFCFA), text: rgb(0x262626), isDark: false),
        ThemePreset(id: "green", name: "护眼绿", bg: rgb(0xE8EFE3), text: rgb(0x26302A), isDark: false),
        ThemePreset(id: "deep",  name: "深夜",   bg: rgb(0x1E1E1E), text: rgb(0xD8D8D8), isDark: true),
    ]

    static func preset(_ id: String) -> ThemePreset {
        all.first { $0.id == id } ?? all[0]
    }

    static func next(after id: String) -> ThemePreset {
        guard let i = all.firstIndex(where: { $0.id == id }) else { return all[0] }
        return all[(i + 1) % all.count]
    }

    private static func rgb(_ hex: UInt32) -> NSColor {
        NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255.0,
                green:   CGFloat((hex >>  8) & 0xFF) / 255.0,
                blue:    CGFloat( hex        & 0xFF) / 255.0,
                alpha: 1)
    }
}

// 字号 / 重排统一交给排版模块的 `func reapplyStyles()`（Editor.swift），
// 主题这边只负责颜色，不重复实现字体逻辑。

// MARK: - 应用主题

extension EditorRoot {

    var themeIsDeep: Bool { ThemePresets.preset(doc.theme).isDark }

    // 启动入口（buildViews 动态派发 installTheme:）：按当前 doc.theme 落一次色
    @objc func installTheme(_ sender: Any?) {
        applyTheme(sender)
    }

    // 应用当前 doc.theme 到整条视图链（只动颜色，不动排版）
    @objc func applyTheme(_ sender: Any?) {
        let preset = ThemePresets.preset(doc.theme)

        applyThemeWindow(preset)        // 1. 窗口外观（标题栏）+ 窗口底色
        applyThemeBackgrounds(preset)   // 2. 自身 / 侧栏 / 滚动区 / 正文底色
        requestStylesRefresh()          // 3. 让排版模块按当前字号重排，再覆盖前景/光标色
        syncOpenThemePanel()            // 4. 「外观」面板开着时同步它的外观与选中态

        // buildViews 里 installTheme: 之后还会再铺一次 Markdown（语义色），
        // 启动路径（还没有 window）延后一拍把预设正文色盖回来。
        if window == nil {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.paintTextColor(ThemePresets.preset(self.doc.theme))
            }
        }
    }

    // 视图菜单 / 顶部按钮入口：在 4 套预设间循环
    @objc func toggleTheme(_ sender: Any?) {
        doc.theme = ThemePresets.next(after: doc.theme).id
        applyTheme(sender)
        persistNow()
    }

    /// 字号/主题变化后重排正文并保住预设正文色。ThemePanel 的滑块直接调它。
    func requestStylesRefresh() {
        reapplyStyles()
        // 排版引擎会按语义色（labelColor）重铺一遍，这里再盖回当前预设的正文色，
        // 保证「切主题 / 拖字号」之后正文色仍是预设值。
        paintTextColor(ThemePresets.preset(doc.theme))
    }

    // MARK: 内部实现

    private func applyThemeWindow(_ preset: ThemePreset) {
        let name: NSAppearance.Name = preset.isDark ? .darkAqua : .aqua
        let apply: () -> Void = { [weak self] in
            guard let self = self else { return }
            self.window?.appearance = NSAppearance(named: name)
            self.window?.backgroundColor = preset.bg
        }
        if window != nil {
            apply()
        } else {
            // buildViews 阶段视图可能还没挂上 window，下一拍再补
            DispatchQueue.main.async(execute: apply)
        }
    }

    private func applyThemeBackgrounds(_ preset: ThemePreset) {
        textView.backgroundColor = preset.bg
        textView.drawsBackground = true
        scrollView.backgroundColor = preset.bg
        scrollView.drawsBackground = true

        // 整窗同色：标题区/侧栏与正文连成一张纸，靠分隔线区隔层次
        wantsLayer = true
        layer?.backgroundColor = preset.bg.cgColor

        sidebarScroll.backgroundColor = preset.bg
        sidebarScroll.drawsBackground = true
        table.backgroundColor = preset.bg

        // 侧栏选中态：浅色用 sourceList（圆角、贴合 Finder 手感），
        // 深色用 plain + regular —— sourceList 在深色下会把选中行文字染成低对比的蓝灰，
        // 而 plain 的整行高亮配白字，对比度稳。
        if #available(macOS 11.0, *) {
            table.style = preset.isDark ? .plain : .sourceList
        }
        table.selectionHighlightStyle = preset.isDark ? .regular : .sourceList
    }

    /// 只改前景色：不碰 .font / .paragraphStyle，所以字号、行距、Markdown 结构都保持原样。
    private func paintTextColor(_ preset: ThemePreset) {
        textView.textColor = preset.text
        textView.insertionPointColor = preset.text

        var typing = textView.typingAttributes
        typing[.foregroundColor] = preset.text
        textView.typingAttributes = typing

        guard let storage = textView.textStorage else { return }
        let full = NSRange(location: 0, length: storage.length)
        guard full.length > 0 else { return }

        storage.addAttribute(.foregroundColor, value: preset.text, range: full)

        // 引用块保留一档层次：比正文淡，深浅主题各取一个合适的透明度
        guard doc.markdown else { return }
        let quoteColor = preset.text.withAlphaComponent(preset.isDark ? 0.60 : 0.55)
        (storage.string as NSString).enumerateSubstrings(in: full, options: .byLines) { line, _, enclosing, _ in
            guard let line = line?.trimmingCharacters(in: .whitespaces),
                  line.hasPrefix(">") else { return }
            storage.addAttribute(.foregroundColor, value: quoteColor, range: enclosing)
        }
    }

    private func syncOpenThemePanel() {
        if let sheet = window?.attachedSheet as? ThemePanelWindow {
            sheet.syncAppearance()
        }
    }
}
