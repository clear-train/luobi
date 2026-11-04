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

/// 指南与正文用同一套宋体，避免「弹窗像另一个软件」
private func guideSerif(_ size: CGFloat, bold: Bool = false) -> NSFont {
    let names = bold ? ["STSongti-SC-Bold", "SongtiSC-Bold", "STSongti-SC-Black"]
                     : ["STSongti-SC-Regular", "SongtiSC-Regular"]
    for n in names {
        if let f = NSFont(name: n, size: size) { return f }
    }
    return bold ? NSFont.boldSystemFont(ofSize: size) : NSFont.systemFont(ofSize: size)
}

private let guideTitleFont    = guideSerif(25, bold: true)
private let guideSectionFont  = guideSerif(16, bold: true)
private let guideBodyFont     = guideSerif(14)
private let guideKeyFont      = NSFont.monospacedSystemFont(ofSize: 12.5, weight: .semibold)
private let guidePathFont     = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
private let guideNoteFont     = guideSerif(12.5)
private let guideQuestionFont = guideSerif(13.5, bold: true)

private let guideKeyColumn: CGFloat = 104   // 快捷键表格第二列的起始位置
private let guideTextWidth: CGFloat = 552
private let guideTextHeight: CGFloat = 540
private let guideMargin: CGFloat = 24
private let guidePanelWidth: CGFloat = 600
private let guidePanelHeight: CGFloat = 640

// MARK: - 正文（标题 + 七个分区）

private func guideParagraph(spacingBefore: CGFloat = 0,
                            spacingAfter: CGFloat = 0,
                            tabStops: [NSTextTab] = []) -> NSParagraphStyle {
    let p = NSMutableParagraphStyle()
    p.lineSpacing = 7
    p.paragraphSpacingBefore = spacingBefore
    p.paragraphSpacing = spacingAfter
    p.tabStops = tabStops
    return p
}

private func guideText(preset: ThemePreset) -> NSAttributedString {
    let ink = preset.text
    let note = preset.text.withAlphaComponent(0.58)
    let out = NSMutableAttributedString()
    let tabStops = [NSTextTab(textAlignment: .left, location: guideKeyColumn, options: [:])]

    func add(_ text: String, font: NSFont, color: NSColor? = nil,
             before: CGFloat = 0, after: CGFloat = 0) {
        out.append(NSAttributedString(string: text + "\n", attributes: [
            .font: font,
            .foregroundColor: color ?? ink,
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
            .foregroundColor: ink,
            .paragraphStyle: p,
        ]))
        out.append(NSAttributedString(string: desc + "\n", attributes: [
            .font: guideBodyFont,
            .foregroundColor: ink,
            .paragraphStyle: p,
        ]))
    }

    func path(_ text: String) {
        out.append(NSAttributedString(string: "   " + text + "\n", attributes: [
            .font: guidePathFont,
            .foregroundColor: ink,
            .paragraphStyle: guideParagraph(spacingAfter: 4),
        ]))
    }

    func question(_ text: String) {
        add(text, font: guideQuestionFont, before: 6, after: 1)
    }

    // 抬头
    add("落笔 · 使用指南", font: guideTitleFont, after: 2)
    add("一个本地、安静、只为你自己的写作工具。随时可以从「帮助 → 功能说明与使用指南」再打开这里。",
        font: guideNoteFont, color: note, after: 2)

    // 1 欢迎
    section("欢迎")
    add("分组和每一篇文稿都保存在你电脑上的同一个 JSON 文件里，不联网、不同步、不打扰。想法来了就写，别的交给工具。",
        font: guideBodyFont, after: 2)
    bullet("打开先到**书库**：一本书一张卡，点哪本写哪本。左边是文稿树，中间是一张纸——需要的都在眼前。")

    // 2 三步开始
    section("三步开始")
    bullet("一、书库里点一本书（或右上角「＋ 新建书」建一本）。")
    bullet("二、侧栏顶部「＋」下拉里选「新建文稿」或「新建分组」；分组可以再嵌分组。")
    bullet("三、光标已经停在正文末尾，直接写第一句。停手 0.8 秒自动保存。")

    // 3 界面导览
    section("界面导览")
    bullet("左侧栏是一棵树：分组是文件夹，文稿是叶子。点文稿切换，把文稿拖到分组上就归档。")
    bullet("侧栏右上角的 « 一键收起左侧栏，只剩一张纸；收起后窗口最左边会出现 » 用来展开。左上角「‹ 书库」随时回书库换书。")
    bullet("中间纸张就是正文。标题在编辑区顶部，点进去直接改，改完即存。")
    bullet("顶栏只剩两个环：🍅 番茄钟和「今」今日进度。鼠标停在番茄上，会浮出今天写了多少字、几个番茄、专注多久。其余动作在菜单栏图标（窗口右上角常驻）和应用菜单里。")
    bullet("Markdown 实时排版：# 到 ###### 是六级标题，**加粗** 用双星号，> 开头是引用（灰色斜体）。标记保留在正文里，导出仍是 Markdown。")
    bullet("底部状态栏显示书名、篇数、「本篇 N 字 · 本书 N 字」和保存状态。写作目标、统计、指南都在菜单栏图标的下拉菜单里。")
    add("按钮都能点，不用记快捷键。",
        font: guideNoteFont, color: note, before: 2, after: 2)

    // 4 外观
    section("外观")
    bullet("点顶部「外观」打开面板，选一套配色：羊皮纸、米白、护眼绿、深夜。")
    bullet("正文字号 15–20pt，拖动滑块即时生效，不用点确定。")
    bullet("选完自动保存，下次打开还是这一套。")

    // 5 文稿管理
    section("文稿管理")
    bullet("新建文稿：侧栏顶部「＋」下拉，或 ⌘N。新建分组：同一个下拉，或右键侧栏空白处。换书：点「‹ 书库」。")
    bullet("归档：把文稿拖到分组上松手；也可以把分组拖进分组，做出嵌套。")
    bullet("重命名：右键文稿或分组 →「重命名」，原地输入，回车确认。")
    bullet("删除：右键 →「删除」是两步确认，先删、再确认一次。")
    add("删除不可撤销，只能靠备份找回：之前拷走的 state.json，或导出过的 Markdown。",
        font: guideNoteFont, color: note, before: 2, after: 2)

    // 5.5 写成一本以后
    section("写成一本以后")
    bullet("大纲板（视图菜单）：章节平铺成卡片墙，看全书的长度和分布，拖动可重排，点一下进入那一章。")
    bullet("阅读模式（视图菜单）：藏起所有控件、正文只读、← → 翻篇、Esc 退出，通读改稿时用。")
    bullet("查找替换（⌘F）：改人名、统一用词，范围可选「仅此篇 / 当前分组 / 全库」，替换前自动备份。")
    bullet("历史版本（右键章节）：每次改动自动留一份，能看能恢复；每篇最多 40 份。")
    bullet("逐章目标（右键章节）：给一章设个字数额度，大纲板上会标「偏短 / 刚好 / 偏长」。")
    bullet("人物卡片：侧栏右键「新建人物卡」；⌘ 点正文里的名字会弹出卡片。视图菜单里有「人物一览」和「人物关系图」。")
    bullet("番茄钟：顶部的环（里面是 T）点一下开始专注。暂停后再点一下是「继续」，进度不会丢。到点以后不会打断你，而是变橙、开始正计时（+05:20），你想停就停。")
    bullet("番茄时长自己定：视图菜单 → 番茄钟时长设置，专注和休息分别设多少分钟都行。菜单栏的小图标也跟着计时。")
    bullet("写作统计（视图菜单）：最近 30 天的字数柱状图、连续达标天数、目标线，还有「今天写了多少分钟」——只统计真正在打字的时间。")
    bullet("写作节奏（视图菜单）：按小时看你的产量。哪一点写得最多、哪一点最没效率、最快手速多少字/分钟，以及「拐点」——峰值之后掉到一半以下的那个小时，到了就适合收尾。")

    // 6 数据在哪
    section("数据在哪")
    bullet("整个文稿库——分组、文稿、偏好——只有一个 JSON 文件：")
    path("~/Library/Application Support/Luobi/state.json")
    bullet("导出的 Markdown 默认落在：")
    path("~/Documents/Luobi/")
    bullet("同一目录下还有两个文件夹：Backups/（整库快照，每 5 分钟一份，最多 20 份）和 History/<文稿 id>/（单篇历史，普通 .md 文件）。")
    bullet("复制这个 JSON 就是完整备份；换电脑时放回同一路径，打开就是原来的文库。")
    bullet("建议定期备份，比如每周拷一次，文件名带上日期。")

    // 7 快捷键
    section("快捷键")
    shortcut("⌘N", "新建文稿")
    shortcut("⌘S", "保存")
    shortcut("⌘O", "导入 Markdown")
    shortcut("⌘E", "导出")
    shortcut("⌘F", "查找与替换")
    add("只剩这五个，其余全部靠点击：工具栏按钮、右键菜单、菜单栏。编辑动作照旧：⌘Z 撤销、⇧⌘Z 重做，⌘C / ⌘V / ⌘X / ⌘A 照常。",
        font: guideNoteFont, color: note, before: 4, after: 2)

    // 页脚
    add("本指南只读，可以选中文字复制路径。按 Esc 或点右下角「开始写作」关闭，回到正文继续写。",
        font: guideNoteFont, color: note, before: 12, after: 0)

    return out
}

// MARK: - 面板搭建

private func makeGuidePanel(host: NSWindow?, preset: ThemePreset) -> GuideSheetWindow {
    let width = guidePanelWidth
    let height = guidePanelHeight

    let panel = GuideSheetWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: height),
                                 styleMask: [.titled, .closable],
                                 backing: .buffered, defer: false)
    panel.title = "使用指南"
    panel.isReleasedWhenClosed = false
    panel.hostWindow = host
    panel.appearance = NSAppearance(named: preset.isDark ? .darkAqua : .aqua)
    panel.backgroundColor = preset.bg

    let content = NSView(frame: NSRect(x: 0, y: 0, width: width, height: height))
    content.wantsLayer = true
    content.layer?.backgroundColor = preset.bg.cgColor

    // 正文：只读、可滚动的 NSTextView，纸张色调与主窗口一致
    let scroll = NSTextView.scrollableTextView()
    scroll.frame = NSRect(x: guideMargin,
                          y: 76,
                          width: guideTextWidth,
                          height: height - 76 - 24)
    scroll.hasVerticalScroller = true
    scroll.autohidesScrollers = true
    scroll.borderType = .noBorder
    scroll.drawsBackground = false
    scroll.scrollerStyle = .overlay

    if let tv = scroll.documentView as? NSTextView {
        tv.frame = NSRect(x: 0, y: 0, width: guideTextWidth, height: scroll.frame.height)
        tv.isEditable = false
        tv.isSelectable = true
        tv.drawsBackground = false
        tv.font = guideBodyFont
        tv.textColor = preset.text
        tv.insertionPointColor = preset.text
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
        tv.textStorage?.setAttributedString(guideText(preset: preset))
        tv.setSelectedRange(NSRange(location: 0, length: 0))
    }

    // 底部按钮区上方的分隔线
    let separator = NSBox(frame: NSRect(x: guideMargin, y: 64,
                                        width: width - guideMargin * 2, height: 1))
    separator.boxType = .separator

    // 右下角两个按钮：主按钮回车即触发
    let confirm = NSButton(title: "开始写作", target: panel,
                           action: #selector(GuideSheetWindow.dismissGuide(_:)))
    confirm.bezelStyle = .rounded
    confirm.controlSize = .regular
    confirm.font = guideSerif(13)
    confirm.keyEquivalent = "\r"
    confirm.frame = NSRect(x: width - guideMargin - 104, y: 22, width: 104, height: 28)
    confirm.autoresizingMask = [.minXMargin]

    let close = NSButton(title: "知道了", target: panel,
                         action: #selector(GuideSheetWindow.dismissGuide(_:)))
    close.bezelStyle = .rounded
    close.controlSize = .regular
    close.font = guideSerif(13)
    close.frame = NSRect(x: width - guideMargin - 104 - 88, y: 22, width: 80, height: 28)
    close.autoresizingMask = [.minXMargin]

    content.addSubview(scroll)
    content.addSubview(separator)
    content.addSubview(close)
    content.addSubview(confirm)

    panel.contentView = content
    panel.initialFirstResponder = confirm
    return panel
}

// MARK: - 菜单动作

extension EditorRoot {

    /// 帮助菜单「使用指南」：把指南作为 sheet 挂到主窗口上。
    @objc func showGuide(_ sender: Any?) {
        guard let host = window else {
            // 理论上不会发生（文档窗口一定存在），兜底成独立窗口。
            let panel = makeGuidePanel(host: nil, preset: ThemePresets.preset(doc.theme))
            panel.center()
            panel.makeKeyAndOrderFront(nil)
            return
        }

        // 已经开着就不再叠一层；若开着别的 sheet（例如目标字数对话框）也不抢。
        if let sheet = host.attachedSheet {
            if sheet is GuideSheetWindow { host.makeKeyAndOrderFront(nil) }
            return
        }

        let panel = makeGuidePanel(host: host, preset: ThemePresets.preset(doc.theme))
        host.beginSheet(panel) { [weak self] _ in
            // 关掉指南后把光标还给正文，接着写。
            guard let self = self else { return }
            self.window?.makeFirstResponder(self.textView)
        }
    }
}
