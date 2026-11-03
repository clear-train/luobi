import Foundation
import AppKit

// MARK: - 数据模型与文稿库

struct DocState: Codable {
    var title: String = "未命名"
    var content: String = "第一次打开。\n\n在下面开始写你的第一章吧。"
}

enum Vault {
    static var dir: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("UlyssesNative", isDirectory: true)
    }
    static var file: URL { dir.appendingPathComponent("state.json") }

    static func ensure() {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    static func load() -> DocState {
        ensure()
        guard let data = try? Data(contentsOf: file) else { return DocState() }
        return (try? JSONDecoder().decode(DocState.self, from: data)) ?? DocState()
    }

    static func save(_ doc: DocState) -> Bool {
        ensure()
        do {
            let tmp = file.appendingPathExtension("tmp")
            try JSONEncoder().encode(doc).write(to: tmp, options: .atomic)
            try? FileManager.default.removeItem(at: file)
            try FileManager.default.moveItem(at: tmp, to: file)
            return true
        } catch {
            return false
        }
    }
}

// MARK: - 统计

func statCJK(_ s: String) -> Int {
    s.unicodeScalars.filter { u in
        (0x2E80...0x9FFF).contains(u.value)
            || (0x3400...0x4DBF).contains(u.value)
            || (0xF900...0xFAFF).contains(u.value)
            || (0x3040...0x30FF).contains(u.value)
    }.count
}

func statLatin(_ s: String) -> Int {
    var n = 0
    var inWord = false
    for u in s.unicodeScalars {
        let isLetter = u.value < 0x80 && (u.properties.isAlphabetic || u.properties.numericType != nil)
        if isLetter {
            if !inWord { n += 1; inWord = true }
        } else {
            inWord = false
        }
    }
    return n
}

// MARK: - 编辑器界面（AppKit：手ケード约束，无宏依赖）

final class EditorRoot: NSView, NSTextViewDelegate, NSTextFieldDelegate {
    var titleInput = NSTextField()
    var scrollView = NSScrollView()
    var textView = NSTextView()
    var barLabel = NSTextField()
    var saveTimer: Timer? = nil

    private(set) var doc = Vault.load()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        buildViews()
    }

    required init?(coder: NSCoder) { fatalError("不走 storyboard") }

    private func buildViews() {
        wantsLayer = true

        // 标题输入框
        titleInput = NSTextField()
        titleInput.stringValue = doc.title
        titleInput.isBordered = false
        titleInput.drawsBackground = false
        titleInput.placeholderString = "给这篇起个名字"
        titleInput.font = NSFont.boldSystemFont(ofSize: 22)
        titleInput.delegate = self
        titleInput.translatesAutoresizingMaskIntoConstraints = false

        // 滚动区 + 正文
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        textView = NSTextView()
        textView.isRichText = false
        textView.string = doc.content
        textView.font = NSFont.systemFont(ofSize: 17)
        textView.delegate = self
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.autoresizingMask = [.width]
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.textContainerInset = NSSize(width: 24, height: 24)
        scrollView.documentView = textView

        // 底部信息栏
        barLabel = NSTextField(labelWithString: "")
        barLabel.font = NSFont.systemFont(ofSize: 11)
        barLabel.textColor = .secondaryLabelColor
        barLabel.translatesAutoresizingMaskIntoConstraints = false
        refreshBar()

        addSubview(titleInput)
        addSubview(scrollView)
        addSubview(barLabel)

        NSLayoutConstraint.activate([
            titleInput.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            titleInput.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 24),
            titleInput.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -24),

            scrollView.topAnchor.constraint(equalTo: titleInput.bottomAnchor, constant: 8),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),

            barLabel.topAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: 6),
            barLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 24),
            barLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -24),
            barLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),
        ])

        // 让光标直接落在正文里，一打开就能写
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.window?.makeFirstResponder(self.textView)
            self.textView.setSelectedRange(NSRange(location: self.doc.content.utf16.count, length: 0))
        }
    }

    // MARK: 变化 → 保存（800ms 防抖）

    private func markDirty() {
        refreshBar()
        saveTimer?.invalidate()
        saveTimer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: false) { [weak self] _ in
            self?.persistNow()
        }
    }

    private func persistNow() {
        let ok = Vault.save(doc)
        refreshBar(saved: ok)
    }

    private func refreshBar(saved: Bool? = nil) {
        let n = statCJK(doc.content) + statLatin(doc.content)
        let count = n == 0 ? "尚无字数" : "约 \(n) 字"
        if let saved = saved {
            barLabel.stringValue = "Ulysses Native · " + count + " · " + (saved ? "已自动保存" : "保存失败")
        } else {
            barLabel.stringValue = "Ulysses Native · " + count
        }
    }

    // MARK: 委托回调

    func controlTextDidChange(_ obj: Notification) { // 标题变化
        guard (obj.object as? NSTextField) === titleInput else { return }
        doc.title = titleInput.stringValue
        markDirty()
    }

    func textDidChange(_ notification: Notification) { // 正文变化
        doc.content = textView.string
        markDirty()
    }
}

// MARK: - 组装窗口与菜单

let app = NSApplication.shared

let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 960, height: 660),
                   styleMask: [.titled, .closable, .miniaturizable, .resizable],
                   backing: .buffered, defer: false)
win.title = "Ulysses Native"
win.minSize = NSSize(width: 640, height: 440)
win.contentView = EditorRoot()
win.center()
win.setFrameAutosaveName("UlyssesNativeMain")
win.makeKeyAndOrderFront(nil)

// 菜单：编辑菜单一接上，系统级撤销/重做/剪切/粘贴就全部生效
let main = NSMenu()
for (name, items) in [
    ("应用", [
        NSMenuItem(title: "退出 Ulysses Native", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
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
