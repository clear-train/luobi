import Foundation
import AppKit

// MARK: - 数据模型与文稿库

struct DocState: Codable {
    var title: String = "未命名"
    var content: String = "第一次打开。\n\n在下面开始写你的第一章吧。"
    var typewriter: Bool = true
    var markdown: Bool = true
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
        textView.isRichText = true        // 要挂自定义属性（粗体/字号），只能走富文本
        textView.usesFontPanel = false    // 但不让用户手动改格式，排版权在我们手里
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
            if self.doc.typewriter {
                self.textView.centerSelectionInVisibleArea(nil)
            }
        }
    }

    // MARK: 变化 → 保存（800ms 防抖）

    private var styleTimer: Timer? = nil

    // 100ms 防抖的排版：比保存更频繁（所见即所得要跟手），但不逐键跑
    private func restyleSoon() {
        styleTimer?.invalidate()
        styleTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: false) { [weak self] _ in
            self?.applyMarkdownStyling()
        }
    }

    // 底座样式和档位表：以后想调字号/颜色只改这里
    private let baseFont = NSFont.systemFont(ofSize: 17)
    private let headingFonts: [NSFont] = [
        NSFont.boldSystemFont(ofSize: 26),
        NSFont.boldSystemFont(ofSize: 23),
        NSFont.boldSystemFont(ofSize: 20),
        NSFont.boldSystemFont(ofSize: 18),
        NSFont.boldSystemFont(ofSize: 17),
        NSFont.boldSystemFont(ofSize: 16),
    ]

    private func applyMarkdownStyling() {
        let storage = textView.textStorage!
        let full = NSRange(location: 0, length: storage.length)
        guard doc.markdown else {
            storage.setAttributes([.font: baseFont], range: full)
            return
        }
        storage.setAttributes([
            .font: baseFont,
            .foregroundColor: NSColor.labelColor,
        ], range: full)

        let ns = storage.string as NSString
        if full.length == 0 { return }
        ns.enumerateSubstrings(in: full, options: [.byLines]) { [weak self] line, sub, enclosing, _ in
            guard let self = self, let line = line else { return }
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { return }

            // # 标题：数井号定档位
            let hashes = trimmed.prefix { $0 == "#" }
            let hashCount = hashes.count
            if hashCount >= 1 && hashCount <= 6 {
                let rest = trimmed.dropFirst(hashCount)
                if rest.isEmpty || rest.hasPrefix(" ") || rest.hasPrefix("\t") {
                    let para = NSMutableParagraphStyle()
                    para.paragraphSpacing = 8
                    storage.addAttributes([
                        .font: self.headingFonts[hashCount - 1],
                        .paragraphStyle: para,
                    ], range: enclosing)
                    return
                }
            }

            // **加粗**：成对找
            var searchStart = line.startIndex
            var opens: [String.Index] = []
            while let first = line.range(of: "**", range: searchStart..<line.endIndex) {
                if let close = line.range(of: "**", range: first.upperBound..<line.endIndex) {
                    let inner = first.upperBound..<close.lowerBound
                    let rangeInDoc = NSRange(inner, in: line)
                    let shifted = NSRange(location: enclosing.location + rangeInDoc.location,
                                          length: rangeInDoc.length)
                    if shifted.length > 0 {
                        storage.addAttributes([.font: NSFont.boldSystemFont(ofSize: 17)],
                                              range: shifted)
                    }
                    searchStart = close.upperBound
                } else {
                    break
                }
            }

            // > 引用
            if trimmed.hasPrefix(">") {
                storage.addAttributes([
                    .font: NSFontManager.shared.convert(baseFont, toHaveTrait: [.italicFontMask]),
                    .foregroundColor: NSColor.secondaryLabelColor,
                ], range: enclosing)
                return
            }
        }
    }

    private func markDirty() {
        refreshBar()
        restyleSoon()
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
        if doc.typewriter {
            DispatchQueue.main.async { [weak self] in
                self?.textView.centerSelectionInVisibleArea(nil)
            }
        }
    }

    // MARK: 菜单动作（走响应链：menuItem.target=nil，谁在响应链顶谁接）

    @objc func toggleTypewriter(_ sender: Any?) {
        doc.typewriter.toggle()
        persistNow()
    }

    @objc func toggleMarkdown(_ sender: Any?) {
        doc.markdown.toggle()
        applyMarkdownStyling()
        persistNow()
    }

    @objc func saveNow(_ sender: Any?) {
        persistNow()
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
        NSMenuItem(title: "退出 Ulysses Native", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"),
    ]),
    ("文件", [
        NSMenuItem(title: "立即保存", action: Selector(("saveNow:")), keyEquivalent: "s"),
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
