import AppKit

// MARK: - 组装：窗口 + 菜单（唯一有顶层代码的文件）

let app = NSApplication.shared

let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1080, height: 680),
                   styleMask: [.titled, .closable, .miniaturizable, .resizable],
                   backing: .buffered, defer: false)
win.title = "落笔"
win.minSize = NSSize(width: 780, height: 460)

// 标题栏做成「纸张的延续」：无边框、无标题、透明，整窗就是一张羊皮纸，
// 避免顶部那条浅色/带色横条和内容区割裂。
win.styleMask.insert(.fullSizeContentView)
win.titlebarAppearsTransparent = true
win.titleVisibility = .hidden
win.isMovableByWindowBackground = true
win.titlebarSeparatorStyle = .none
win.backgroundColor = NSColor(srgbRed: 0.965, green: 0.949, blue: 0.906, alpha: 1)

// 外壳：书库和写作界面互换。首次启动进书库（挑一本书再开始），
// 之后记住上次退在哪。
let shell = Shell(frame: win.contentLayoutRect)
win.contentView = shell
shell.reload()
win.center()
win.setFrameAutosaveName("LuobiMain")
win.makeKeyAndOrderFront(nil)

let main = NSMenu()
for (name, items) in [
    ("应用", [
        NSMenuItem(title: "退出 落笔", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"),
    ]),
    ("文件", [
        NSMenuItem(title: "新建文稿", action: Selector(("addSheet:")), keyEquivalent: "n"),
        NSMenuItem(title: "新建人物卡", action: Selector(("newCardSheet:")), keyEquivalent: ""),
        NSMenuItem(title: "导入 Markdown…", action: Selector(("importMDFiles:")), keyEquivalent: "o"),
        { let s = NSMenuItem.separator(); return s }(),
        NSMenuItem(title: "导出当前文稿…", action: Selector(("exportActiveSheet:")), keyEquivalent: "e"),
        NSMenuItem(title: "导出全部文稿…", action: Selector(("exportAllSheets:")), keyEquivalent: ""),
        NSMenuItem(title: "导出整本书…", action: Selector(("exportBook:")), keyEquivalent: ""),
        { let s = NSMenuItem.separator(); return s }(),
        NSMenuItem(title: "删除当前文稿…", action: Selector(("deleteActiveSheet:")), keyEquivalent: ""),
        NSMenuItem(title: "立即保存", action: Selector(("saveNow:")), keyEquivalent: "s"),
        { let s = NSMenuItem.separator(); return s }(),
        NSMenuItem(title: "立即备份一份", action: Selector(("backupNow:")), keyEquivalent: ""),
        NSMenuItem(title: "从备份恢复…", action: Selector(("showBackupPanel:")), keyEquivalent: ""),
        NSMenuItem(title: "打开备份文件夹", action: Selector(("openBackupFolder:")), keyEquivalent: ""),
    ]),
    ("编辑", [
        NSMenuItem(title: "撤销", action: Selector(("undo:")), keyEquivalent: "z"),
        NSMenuItem(title: "重做", action: Selector(("redo:")), keyEquivalent: "Z"),
        { let s = NSMenuItem.separator(); return s }(),
        NSMenuItem(title: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x"),
        NSMenuItem(title: "拷贝", action: #selector(NSText.copy(_:)), keyEquivalent: "c"),
        NSMenuItem(title: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v"),
        NSMenuItem(title: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"),
        { let s = NSMenuItem.separator(); return s }(),
        NSMenuItem(title: "查找与替换…", action: Selector(("showReplacePanel:")), keyEquivalent: "f"),
        { let s = NSMenuItem.separator(); return s }(),
        NSMenuItem(title: "本篇历史版本…", action: Selector(("showHistoryPanel:")), keyEquivalent: ""),
        NSMenuItem(title: "设置本章目标…", action: Selector(("setChapterTarget:")), keyEquivalent: ""),
    ]),
    ("视图", [
        NSMenuItem(title: "返回书库", action: Selector(("showLibraryAction:")), keyEquivalent: ""),
        NSMenuItem(title: "显示/收起侧栏", action: Selector(("toggleSidebar:")), keyEquivalent: ""),
        NSMenuItem(title: "新建页面", action: Selector(("addSheet:")), keyEquivalent: ""),
        NSMenuItem(title: "新建章节", action: Selector(("addChapter:")), keyEquivalent: ""),
        NSMenuItem(title: "新建分组", action: Selector(("addFolder:")), keyEquivalent: ""),
        { let s = NSMenuItem.separator(); return s }(),
        NSMenuItem(title: "大纲板…", action: Selector(("showBoard:")), keyEquivalent: ""),
        NSMenuItem(title: "阅读模式（← → 翻篇）", action: Selector(("toggleReading:")), keyEquivalent: ""),
        NSMenuItem(title: "打字机居中", action: Selector(("toggleTypewriter:")), keyEquivalent: ""),
        NSMenuItem(title: "Markdown 排版", action: Selector(("toggleMarkdown:")), keyEquivalent: ""),
        NSMenuItem(title: "外观（主题与字号）…", action: Selector(("showThemePanel:")), keyEquivalent: ""),
        NSMenuItem(title: "今日写作目标…", action: Selector(("showGoalPanel:")), keyEquivalent: ""),
        NSMenuItem(title: "写作统计…", action: Selector(("showStatsPanel:")), keyEquivalent: ""),
        NSMenuItem(title: "写作节奏（我什么时候写得动）…", action: Selector(("showRhythmPanel:")), keyEquivalent: ""),
        NSMenuItem(title: "番茄钟：开始/暂停/继续", action: Selector(("togglePomodoro:")), keyEquivalent: ""),
        NSMenuItem(title: "番茄钟时长设置…", action: Selector(("showPomodoroSettings:")), keyEquivalent: ""),
        NSMenuItem(title: "人物一览…", action: Selector(("showCardsOverview:")), keyEquivalent: ""),
        NSMenuItem(title: "人物关系图…", action: Selector(("showRelationGraph:")), keyEquivalent: ""),
        { let s = NSMenuItem.separator(); return s }(),
        NSMenuItem(title: "影子模式（和过去的自己比）", action: Selector(("toggleShadowMode:")), keyEquivalent: ""),
    ]),
    ("窗口", [
        NSMenuItem(title: "最小化", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m"),
        NSMenuItem(title: "关闭", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"),
    ]),
    ("帮助", [
        NSMenuItem(title: "设置…", action: Selector(("showSettingsPanel:")), keyEquivalent: ","),
        NSMenuItem(title: "功能说明与使用指南", action: Selector(("showGuide:")), keyEquivalent: ""),
        NSMenuItem(title: "打开文稿库文件夹", action: Selector(("openVaultFolder:")), keyEquivalent: ""),
    ]),
] as [(String, [NSMenuItem])] {
    let root = NSMenuItem()
    main.addItem(root)
    let m = NSMenu(title: name)
    root.submenu = m
    items.forEach(m.addItem)
}
main.autoenablesItems = false
app.mainMenu = main

app.setActivationPolicy(.regular)
app.run()
