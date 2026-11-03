import AppKit

// MARK: - 主题模块：paper 羊皮纸 | deep 深夜
// 只负责「颜色观感」：坐标纸底色 + 窗口外观 + 正文前景遮罩。
// 排版引擎（applyMarkdownStyling）继续用 .labelColor/.secondaryLabelColor
// 语义色——窗口外观一换它们天然适配双主题，这里不写死任何黑/白。

// extension 不能存属性，色板放文件级常量
private let themePaperBackground = NSColor(calibratedRed: 246.0/255.0, green: 242.0/255.0, blue: 231.0/255.0, alpha: 1) // #F6F2E7
private let themeDeepBackground  = NSColor(calibratedRed:  30.0/255.0, green:  30.0/255.0, blue:  30.0/255.0, alpha: 1) // #1E1E1E 近似

extension EditorRoot {

    var themeIsDeep: Bool { doc.theme == "deep" }

    // 启动入口（buildViews 动态派发 installTheme:）：按当前 doc.theme 落一次色
    @objc func installTheme(_ sender: Any?) {
        applyTheme(sender)
    }

    // 应用当前 doc.theme 到视图链
    @objc func applyTheme(_ sender: Any?) {
        let deep = themeIsDeep

        // --- 窗口外观先行（标题栏/侧栏跟随主题），正文语义色随后按新外观解析 ---
        applyThemeWindowAppearance(deep: deep)

        // --- 编辑区坐标纸 ---
        let bg = deep ? themeDeepBackground : themePaperBackground
        textView.backgroundColor = bg
        textView.drawsBackground = true
        scrollView.backgroundColor = bg
        scrollView.drawsBackground = true

        // --- 整窗同色：标题区/侧栏与正文连成一张纸，靠分隔线区隔层次 ---
        wantsLayer = true
        layer?.backgroundColor = bg.cgColor
        sidebarScroll.backgroundColor = bg
        sidebarScroll.drawsBackground = true
        table.backgroundColor = bg

        // --- 正文前景 ---
        // deep：显式下发 .textColor（在 darkAqua 窗口下解析为浅色，
        //       避免浅色系统外观下黑字融进深夜底）。
        // paper：回到 .labelColor，正文保持黑字。
        let foreground: NSColor = deep ? NSColor.textColor : NSColor.labelColor
        textView.textColor = foreground
        textView.insertionPointColor = foreground
        var typing = textView.typingAttributes
        typing[.foregroundColor] = foreground
        textView.typingAttributes = typing

        // 排版引擎先铺语义色（字号/加粗/引用斜体等排版逻辑原样不动），
        // 再把主题前景遮罩盖到全文，避免旧属性残留。
        applyMarkdownStyling()
        let storage = textView.textStorage!
        let full = NSRange(location: 0, length: storage.length)
        storage.addAttributes([.foregroundColor: foreground], range: full)
    }

    // 视图菜单入口：paper <-> deep 切换、存盘、重应用
    @objc func toggleTheme(_ sender: Any?) {
        doc.theme = themeIsDeep ? "paper" : "deep"
        applyTheme(sender)
        persistNow()
    }

    // buildViews 阶段 view 可能尚未挂上 window，兜底到下一拍再切外观
    private func applyThemeWindowAppearance(deep: Bool) {
        let name: NSAppearance.Name = deep ? NSAppearance.Name.darkAqua : NSAppearance.Name.aqua
        if let win = window {
            win.appearance = NSAppearance(named: name)
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.window?.appearance = NSAppearance(named: name)
            }
        }
    }
}
