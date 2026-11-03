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
private let guideTextHeight: CGFloat = 528
private let guideMargin: CGFloat = 20

// MARK: - 正文（标题 + 七个分区）

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
    add("一个本地、安静、只为你自己的写作工具。随时可以从「帮助 → 使用指南」再打开这里。",
        font: guideNoteFont, color: .secondaryLabelColor, after: 2)

    // 1 欢迎
    section("欢迎")
    add("分组和每一篇文稿都保存在你电脑上的同一个 JSON 文件里，不联网、不同步、不打扰。想法来了就写，别的交给工具。",
        font: guideBodyFont, after: 2)
    bullet("左边是文稿树，中间是一张纸，右上角一排按钮——需要的都在眼前。")

    // 2 三步开始
    section("三步开始")
    bullet("一、点「新建」（或 ⌘N），拿到一张空白的纸。")
    bullet("二、点「▤ 分组」建一个文件夹，把文稿拖进去；分组还可以再嵌分组。")
    bullet("三、光标已经停在正文末尾，直接写第一句。停手 0.8 秒自动保存。")

    // 3 界面导览
    section("界面导览")
    bullet("左侧栏是一棵树：分组是文件夹，文稿是叶子。点文稿切换，拖动可以归档。")
    bullet("顶部「侧栏」按钮一键收起 / 展开侧栏；收起后只剩一张纸，专心写。")
    bullet("中间纸张就是正文。标题在编辑区顶部，点进去直接改，改完即存。")
    bullet("顶部按钮排：新建、▤ 分组、导入、导出、主题、侧栏、指南，每一个都能点。")
    bullet("Markdown 实时排版：# 到 ###### 是六级标题，**加粗** 用双星号，> 开头是引用（灰色斜体）。标记保留在正文里，导出仍是 Markdown。")
    bullet("底部状态栏显示篇数、「约 N 字」和当前的保存状态。")
    add("按钮都能点，不用记快捷键。",
        font: guideNoteFont, color: .secondaryLabelColor, before: 2, after: 2)

    // 4 外观
    section("外观")
    bullet("点顶部「主题」打开外观面板，选一套配色：羊皮纸、米白、护眼绿、深夜。")
    bullet("正文字号 15–20pt，拖动滑块即时生效，不用点确定。")
    bullet("选完自动保存，下次打开还是这一套。")

    // 5 文稿管理
    section("文稿管理")
    bullet("新建文稿：顶部「新建」或 ⌘N。新建分组：顶部「▤ 分组」，或右键侧栏空白处。")
    bullet("归档：把文稿拖到分组上松手；也可以把分组拖进分组，做出嵌套。")
    bullet("重命名：右键文稿或分组 →「重命名」，原地输入，回车确认。")
    bullet("删除：右键 →「删除」是两步确认，先删、再确认一次。")
    add("删除不可撤销，只能靠备份找回：之前拷走的 state.json，或导出过的 Markdown。",
        font: guideNoteFont, color: .secondaryLabelColor, before: 2, after: 2)

    // 6 数据在哪
    section("数据在哪")
    bullet("整个文稿库——分组、文稿、偏好——只有一个 JSON 文件：")
    path("~/Library/Application Support/UlyssesNative/state.json")
    bullet("导出的 Markdown 默认落在：")
    path("~/Documents/UlyssesNative/")
    bullet("复制这个 JSON 就是完整备份；换电脑时放回同一路径，打开就是原来的文库。")
    bullet("建议定期备份，比如每周拷一次，文件名带上日期。")

    // 7 快捷键
    section("快捷键")
    shortcut("⌘N", "新建文稿")
    shortcut("⌘S", "保存")
    shortcut("⌘O", "导入 Markdown")
    shortcut("⌘E", "导出")
    add("只剩这四个，其余全部靠点击：工具栏按钮、右键菜单、菜单栏。编辑动作照旧：⌘Z 撤销、⇧⌘Z 重做，⌘C / ⌘V / ⌘X / ⌘A 照常。",
        font: guideNoteFont, color: .secondaryLabelColor, before: 4, after: 2)

    // 页脚
    add("本指南只读，可以选中文字复制路径。按 Esc 或点「开始写作」关闭，回到正文继续写。",
        font: guideNoteFont, color: .secondaryLabelColor, before: 12, after: 0)

    return out
}

// MARK: - 面板搭建

private func makeGuidePanel(host: NSWindow?) -> GuideSheetWindow {
    let width = guideTextWidth + guideMargin * 2      // 560
    let height: CGFloat = 620

    let panel = GuideSheetWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: height),
                                 styleMask: [.titled, .closable],
                                 backing: .buffered, defer: false)
    panel.title = "使用指南"
    panel.isReleasedWhenClosed = false
    panel.hostWindow = host

    let content = NSView(frame: NSRect(x: 0, y: 0, width: width, height: height))

    // 正文：只读、可滚动的 NSTextView（520 × 528，内边距 20）
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
