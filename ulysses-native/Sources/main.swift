import AppKit

// MARK: - 组装：窗口 + 菜单（唯一有顶层代码的文件）

let app = NSApplication.shared

let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1080, height: 680),
                   styleMask: [.titled, .closable, .miniaturizable, .resizable],
                   backing: .buffered, defer: false)
win.title = "Ulysses Native"
win.minSize = NSSize(width: 780, height: 460)
win.contentView = EditorRoot()
win.center()
win.setFrameAutosaveName("UlyssesNativeMain")
win.makeKeyAndOrderFront(nil)

let main = NSMenu()
for (name, items) in [
    ("应用", [
        NSMenuItem(title: "退出 Ulysses Native", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"),
    ]),
    ("文件", [
        NSMenuItem(title: "新建文稿", action: Selector(("addSheet:")), keyEquivalent: "n"),
        NSMenuItem(title: "立即保存", action: Selector(("saveNow:")), keyEquivalent: "s"),
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
        {
            let i = NSMenuItem(title: "打字机居中", action: Selector(("toggleTypewriter:")), keyEquivalent: "t")
            i.keyEquivalentModifierMask = [.command, .option]
            return i
        }(),
        {
            let i = NSMenuItem(title: "Markdown 排版", action: Selector(("toggleMarkdown:")), keyEquivalent: "m")
            i.keyEquivalentModifierMask = [.command, .option]
            return i
        }(),
    ]),
    ("窗口", [
        NSMenuItem(title: "最小化", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m"),
        NSMenuItem(title: "关闭", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"),
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
