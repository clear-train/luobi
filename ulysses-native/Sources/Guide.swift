import AppKit

// MARK: - 使用指南面板（帮助菜单 → 使用指南）
//
// 触发链：主菜单「帮助 → 使用指南」→ 响应链找到 EditorRoot 的 showGuide:
// 展示方式：自建 NSPanel，以 sheet 形式附在主窗口上；内容是一个只读、可滚动的
//          NSTextView，用 NSAttributedString 排好版（标题 20pt / 小标题 14pt / 正文 13pt，行距 6）。
//
// 说明：extension 不能新增存储属性，所以面板不进属性；
//      sheet 展示期间由宿主窗口持有，关闭后随窗口一起释放（isReleasedWhenClosed = false，
//      避免 AppKit 在 endSheet 时提前 dealloc 一个仍被按钮 target 引用的实例）。

// MARK: - 面板（带一个能自己结束 sheet 的关闭动作）

final class GuideSheetWindow: NSPanel {

    /// 宿主主窗口。sheet 模式用来 endSheet；独立窗口模式为 nil。
    weak var hostWindow: NSWindow?

    @objc func dismissGuide(_ sender: Any?) {
        guard let host = hostWindow, host.attachedSheet === self else {
            close()
            return
        }
        host.endSheet(self)
    }

    /// Esc 等同于点「开始写作」。
    override func cancelOperation(_ sender: Any?) {
        dismissGuide(sender)
    }
}

// MARK: - 排版常量（extension / 局部函数里不能存属性，统一放文件级）

private let guideTitleFont    = NSFont.boldSystemFont(ofSize: 20)
private let guideSectionFont  = NSFont.boldSystemFont(ofSize: 14)
private let guideBodyFont     = NSFont.systemFont(ofSize: 13)
private let guideKeyFont      = NSFont.monospacedSystemFont(ofSize: 12.5, weight: .semibold)
private let guidePathFont     = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
private let guideNoteFont     = NSFont.systemFont(ofSize: 12)
private let guideQuestionFont = NSFont.systemFont(ofSize: 13, weight: .semibold)

private let guideKeyColumn: CGFloat = 104   // 快捷键表格第二列的起始位置
private let guideTextWidth: CGFloat = 520
private let guideTextHeight: CGFloat = 420
private let guideMargin: CGFloat = 20

// MARK: - 正文（标题 + 五个分区）

private func guideParagraph(spacingBefore: CGFloat = 0,
                            spacingAfter: CGFloat = 0,
                            tabStops: [NSTextTab] = []) -> NSParagraphStyle {
    let p = NSMutableParagraphStyle()
    p.lineSpacing = 6
    p.paragraphSpacingBefore = spacingBefore
    p.paragraphSpacing = spacingAfter
    p.tabStops = tabStops
    return p
}

private func guideText() -> NSAttributedString {
    let out = NSMutableAttributedString()
    let tabStops = [NSTextTab(textAlignment: .left, location: guideKeyColumn, options: [:])]

    func add(_ text: String, font: NSFont, color: NSColor = .labelColor,
             before: CGFloat = 0, after: CGFloat = 0) {
        out.append(NSAttributedString(string: text + "\n", attributes: [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: guideParagraph(spacingBefore: before, spacingAfter: after),
        ]))
    }

    func section(_ title: String) {
        add(title, font: guideSectionFont, before: 14, after: 3)
    }

    func bullet(_ text: String) {
        add("·  " + text, font: guideBodyFont, after: 2)
    }

    func shortcut(_ key: String, _ desc: String) {
        let p = guideParagraph(spacingAfter: 1, tabStops: tabStops)
        out.append(NSAttributedString(string: key + "\t", attributes: [
            .font: guideKeyFont,
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: p,
        ]))
        out.append(NSAttributedString(string: desc + "\n", attributes: [
            .font: guideBodyFont,
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: p,
        ]))
    }

    func path(_ text: String) {
        out.append(NSAttributedString(string: "   " + text + "\n", attributes: [
            .font: guidePathFont,
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: guideParagraph(spacingAfter: 4),
        ]))
    }

    func question(_ text: String) {
        add(text, font: guideQuestionFont, before: 6, after: 1)
    }

    // 抬头
    add("Ulysses Native 使用指南", font: guideTitleFont, after: 2)
    add("一个安静的长文写作工具。随时可以从「帮助 → 使用指南」再打开这里。",
        font: guideNoteFont, color: .secondaryLabelColor, after: 2)

    // 1 写作
    section("写作")
    bullet("侧栏是全部文稿：点击切换，顶部搜索框实时过滤标题与正文，+ 号新建一篇。")
    bullet("右上角一排小按钮是常用命令的入口：新建、导入、导出、打字机、排版、主题、目标和这份指南。")
    bullet("编辑区顶部的大标题可以直接改，改完即时保存，没有「保存」按钮要按。")
    bullet("打字机模式：光标所在行始终停在窗口垂直中间，视线不用上下追。")
    bullet("Markdown 实时排版：# 到 ###### 是六级标题，**加粗** 用双星号包住，> 开头是引用（灰色斜体）。标记符号本身保留在正文里，导出仍是 Markdown。")
    bullet("状态栏显示篇数与「约 N 字」；设过写作目标后，底部细进度条会走进度，达标变绿。")
    bullet("停止输入 0.8 秒自动保存，也可以随时按 ⌘S 立即保存。")

    // 2 快捷键
    section("快捷键")
    shortcut("⌘N", "新建文稿")
    shortcut("⌘S", "立即保存")
    shortcut("⌘O", "导入 Markdown（可多选）")
    shortcut("⌘E", "导出当前文稿")
    shortcut("⌥⌘M", "Markdown 排版开关")
    shortcut("⌥⌘T", "打字机居中开关")
    shortcut("⌥⌘Y", "切换主题（羊皮纸 / 深夜）")
    shortcut("⌥⌘G", "设定写作目标字数")
    shortcut("⌘/", "打开本使用指南")
    add("编辑动作沿用 macOS 习惯：⌘Z 撤销、⇧⌘Z 重做，⌘C / ⌘V / ⌘X / ⌘A 照常。",
        font: guideNoteFont, color: .secondaryLabelColor, before: 4, after: 2)

    // 3 文件在哪里
    section("文件在哪里")
    bullet("全部文稿和设置都在一个 JSON 文件里：")
    path("~/Library/Application Support/UlyssesNative/state.json")
    bullet("导出的 Markdown 默认落在：")
    path("~/Documents/UlyssesNative/")
    bullet("在 Finder 里按 ⇧⌘G，粘贴上面的路径（~ 会展开成你的用户目录）可直接跳过去。")
    bullet("导入 Markdown 只是读取文件、复制成新文稿，原文件不会被改动。")

    // 4 备份与导出
    section("备份与导出")
    bullet("最省事的备份：拷贝 state.json。这一个文件就是全部文稿，换电脑时放回同一路径即可。")
    bullet("更稳的备份：定期按 ⌘E 导出本篇；「文件 → 导出全部文稿…」会把所有文稿合成一个 .md 文件。")
    bullet("导出是追加式命名：同名文件不会被覆盖，会自动变成 -2、-3，所以放心多导几次。")

    // 5 常见问题
    section("常见问题")
    question("中文输入法会吞字吗？")
    add("不会，组字过程中的内容照常进入正文。如果输入时觉得 Markdown 排版有点跳，按 ⌥⌘M 先关掉排版，写完这一段再打开。",
        font: guideBodyFont, after: 2)
    question("字数怎么算？")
    add("中文（含日文假名）按字，英文和数字按词，标点和空格不计；只算正文，不算标题——所以状态栏写「约」。",
        font: guideBodyFont, after: 2)
    question("主题重启后记不住？")
    add("主题存在 state.json 里，⌥⌘Y 切换时会立刻保存。重启后还是羊皮纸的话，先看状态栏有没有「保存失败」，再确认 state.json 没被删除、磁盘没满。",
        font: guideBodyFont, after: 2)
    question("底部进度条怎么不显示？")
    add("写作目标为 0 时它是隐藏的。用 ⌥⌘G 设一个大于 0 的字数就会出现。",
        font: guideBodyFont, after: 2)
    question("删掉的文稿能找回吗？")
    add("删除是两步确认且不可撤销，只能靠备份找回：之前拷走的 state.json，或导出过的 Markdown。",
        font: guideBodyFont, after: 2)

    // 页脚
    add("本指南只读，可以选中文字复制路径。按 Esc 或点「开始写作」关闭，回到正文继续写。",
        font: guideNoteFont, color: .secondaryLabelColor, before: 12, after: 0)

    return out
}

// MARK: - 面板搭建

private func makeGuidePanel(host: NSWindow?) -> GuideSheetWindow {
    let width = guideTextWidth + guideMargin * 2      // 560
    let height: CGFloat = 512

    let panel = GuideSheetWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: height),
                                 styleMask: [.titled, .closable],
                                 backing: .buffered, defer: false)
    panel.title = "使用指南"
    panel.isReleasedWhenClosed = false
    panel.hostWindow = host

    let content = NSView(frame: NSRect(x: 0, y: 0, width: width, height: height))

    // 正文：只读、可滚动的 NSTextView（520 × 420，内边距 20）
    let scroll = NSTextView.scrollableTextView()
    scroll.frame = NSRect(x: guideMargin,
                          y: height - guideMargin - guideTextHeight,
                          width: guideTextWidth,
                          height: guideTextHeight)
    scroll.hasVerticalScroller = true
    scroll.autohidesScrollers = true
    scroll.borderType = .noBorder
    scroll.drawsBackground = false

    if let tv = scroll.documentView as? NSTextView {
        tv.frame = NSRect(x: 0, y: 0, width: guideTextWidth, height: guideTextHeight)
        tv.isEditable = false
        tv.isSelectable = true
        tv.drawsBackground = false
        tv.font = guideBodyFont
        tv.textContainerInset = NSSize(width: guideMargin, height: guideMargin)
        tv.textContainer?.lineFragmentPadding = 0
        tv.textContainer?.widthTracksTextView = true
        tv.textContainer?.heightTracksTextView = false
        tv.textContainer?.containerSize = NSSize(
            width: guideTextWidth - guideMargin * 2,
            height: CGFloat.greatestFiniteMagnitude)
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.autoresizingMask = [.width]
        tv.minSize = NSSize(width: 0, height: 0)
        tv.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
                            height: CGFloat.greatestFiniteMagnitude)
        tv.textStorage?.setAttributedString(guideText())
        tv.setSelectedRange(NSRange(location: 0, length: 0))
    }

    // 分隔线
    let separator = NSBox(frame: NSRect(x: guideMargin, y: 62,
                                        width: guideTextWidth, height: 1))
    separator.boxType = .separator

    // 关闭按钮（默认按钮，回车即触发）
    let button = NSButton(title: "开始写作", target: panel,
                          action: #selector(GuideSheetWindow.dismissGuide(_:)))
    button.bezelStyle = .rounded
    button.controlSize = .regular
    button.font = NSFont.systemFont(ofSize: 13)
    button.keyEquivalent = "\r"
    button.frame = NSRect(x: (width - 132) / 2, y: 20, width: 132, height: 28)
    button.autoresizingMask = [.minXMargin, .maxXMargin]

    content.addSubview(scroll)
    content.addSubview(separator)
    content.addSubview(button)

    panel.contentView = content
    panel.initialFirstResponder = button
    return panel
}

// MARK: - 菜单动作

extension EditorRoot {

    /// 帮助菜单「使用指南」：把指南作为 sheet 挂到主窗口上。
    @objc func showGuide(_ sender: Any?) {
        guard let host = window else {
            // 理论上不会发生（文档窗口一定存在），兜底成独立窗口。
            let panel = makeGuidePanel(host: nil)
            panel.center()
            panel.makeKeyAndOrderFront(nil)
            return
        }

        // 已经开着就不再叠一层；若开着别的 sheet（例如目标字数对话框）也不抢。
        if let sheet = host.attachedSheet {
            if sheet is GuideSheetWindow { host.makeKeyAndOrderFront(nil) }
            return
        }

        let panel = makeGuidePanel(host: host)
        host.beginSheet(panel) { [weak self] _ in
            // 关掉指南后把光标还给正文，接着写。
            guard let self = self else { return }
            self.window?.makeFirstResponder(self.textView)
        }
    }
}
