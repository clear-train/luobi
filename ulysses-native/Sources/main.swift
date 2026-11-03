import AppKit

// MARK: - 组装：窗口 + 菜单（唯一有顶层代码的文件）

let app = NSApplication.shared

let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1080, height: 680),
                   styleMask: [.titled, .closable, .miniaturizable, .resizable],
                   backing: .buffered, defer: false)
win.title = "Ulysses Native"
win.minSize = NSSize(width: 780, height: 460)

// 标题栏做成「纸张的延续」：无边框、无标题、透明，整窗就是一张羊皮纸，
// 避免顶部那条浅色/带色横条和内容区割裂。
win.styleMask.insert(.fullSizeContentView)
win.titlebarAppearsTransparent = true
win.titleVisibility = .hidden
win.isMovableByWindowBackground = true
win.titlebarSeparatorStyle = .none
win.backgroundColor = NSColor(srgbRed: 0.965, green: 0.949, blue: 0.906, alpha: 1)

win.contentView = EditorRoot()
win.center()
win.setFrameAutosaveName("UlyssesNativeMain")
win.makeKeyAndOrderFront(nil)

// 首次启动：自动弹一次使用指南（把 seenGuide 写回，之后不再打扰）
if let root = win.contentView as? EditorRoot, !root.doc.seenGuide {
    root.doc.seenGuide = true
    root.persistNow()
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
        if root.responds(to: Selector(("showGuide:"))) {
            root.perform(Selector(("showGuide:")), with: nil)
        }
    }
}

let main = NSMenu()
for (name, items) in [
    ("应用", [
        NSMenuItem(title: "退出 Ulysses Native", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"),
    ]),
    ("文件", [
        NSMenuItem(title: "新建文稿", action: Selector(("addSheet:")), keyEquivalent: "n"),
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
    ]),
    ("视图", [
        NSMenuItem(title: "显示/收起侧栏", action: Selector(("toggleSidebar:")), keyEquivalent: ""),
        NSMenuItem(title: "新建分组", action: Selector(("addFolder:")), keyEquivalent: ""),
        { let s = NSMenuItem.separator(); return s }(),
        NSMenuItem(title: "打字机居中", action: Selector(("toggleTypewriter:")), keyEquivalent: ""),
        NSMenuItem(title: "Markdown 排版", action: Selector(("toggleMarkdown:")), keyEquivalent: ""),
        NSMenuItem(title: "外观（主题与字号）…", action: Selector(("showThemePanel:")), keyEquivalent: ""),
        NSMenuItem(title: "设定写作目标字数…", action: Selector(("setGoalDialog:")), keyEquivalent: ""),
    ]),
    ("窗口", [
        NSMenuItem(title: "最小化", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m"),
        NSMenuItem(title: "关闭", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"),
    ]),
    ("帮助", [
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
