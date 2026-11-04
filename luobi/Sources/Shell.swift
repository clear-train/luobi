import AppKit

/// 窗口外壳：在「书库」和「写作界面」之间切换。
///
/// 为什么要多这一层：写作界面（EditorRoot）假设自己就是整个窗口，
/// 而书库是一张独立的选择页。把它们做成同一个窗口里互换的两个子视图，
/// 比开两个窗口干净——切换时窗口位置、大小、菜单栏状态都不用重建。
final class Shell: NSView {

    var editor: EditorRoot?
    var library: LibraryView?

    private let paper = NSColor(srgbRed: 0.965, green: 0.949, blue: 0.906, alpha: 1)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = paper.cgColor
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    /// 启动时决定先进哪：上次退在书库就进书库，否则直接进那本书
    func reload() {
        let d = Vault.load()
        if d.libraryOpen {
            showLibrary(doc: d)
        } else {
            openBook(d.activeBookId, doc: d)
        }
    }

    // MARK: - 书库

    @objc func showLibraryAction(_ sender: Any?) { showLibrary() }

    func showLibrary(doc: DocState? = nil) {
        editor?.flushSession()
        editor?.persistNow()
        editor?.removeFromSuperview()
        editor = nil

        var d = doc ?? Vault.load()
        d.libraryOpen = true
        d.syncCurrentBook()
        Vault.save(d)

        let lib = LibraryView(doc: d)
        lib.frame = bounds
        lib.autoresizingMask = [.width, .height]
        lib.onOpenBook = { [weak self] id in self?.openBook(id) }
        lib.onNewBook = { [weak self] in self?.createBookFlow() }
        lib.onQuickNote = { [weak self] in self?.quickNote() }
        lib.onRenameBook = { [weak self] id in self?.renameBookFlow(id) }
        lib.onDeleteBook = { [weak self] id in self?.deleteBookFlow(id) }
        addSubview(lib)
        library = lib
    }

    // MARK: - 写作

    func openBook(_ id: String, doc: DocState? = nil) {
        var d = doc ?? Vault.load()
        guard d.openBook(id) else { showLibrary(doc: d); return }
        d.libraryOpen = false
        d.syncCurrentBook()
        Vault.save(d)

        library?.removeFromSuperview()
        library = nil

        let e = EditorRoot()
        e.libraryBackHandler = { [weak self] in self?.showLibrary() }
        e.frame = bounds
        e.autoresizingMask = [.width, .height]
        addSubview(e)
        e.adoptDoc(d)
        e.startSessionTracking()
        e.installStatusItem()
        editor = e
        window?.makeFirstResponder(e.textView)

        // 首次启动：自动弹一次指南（写在 doc 里，之后不再打扰）
        if !d.seenGuide {
            e.doc.seenGuide = true
            e.persistNow()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                if e.responds(to: Selector(("showGuide:"))) {
                    e.perform(Selector(("showGuide:")), with: nil)
                }
            }
        }
    }

    // MARK: - 书库里的几个动作

    private func createBookFlow() {
        let alert = NSAlert()
        alert.messageText = "新建一本书"
        alert.informativeText = "书与书之间完全独立：文稿、分组、人物卡都分开。"
        alert.addButton(withTitle: "创建")
        alert.addButton(withTitle: "取消")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        field.placeholderString = "书名，例如：枣树"
        alert.accessoryView = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        var d = Vault.load()
        d.syncCurrentBook()
        let id = d.createBook(field.stringValue)
        let sheet = Sheet(id: UUID().uuidString, title: "第一章", content: "")
        if let i = d.books.firstIndex(where: { $0.id == id }) {
            d.books[i].sheets = [sheet]
            d.books[i].activeId = sheet.id
        }
        Vault.save(d)
        openBook(id, doc: d)
    }

    /// 不挑书，随手记一条：落在随笔夹里，直接进编辑
    private func quickNote() {
        var d = Vault.load()
        d.syncCurrentBook()
        let id = d.quickNote()
        guard !id.isEmpty, let eid = d.activeBookId as String? else { return }
        Vault.save(d)
        openBook(eid, doc: d)
    }

    private func renameBookFlow(_ id: String) {
        var d = Vault.load()
        guard let b = d.books.first(where: { $0.id == id }) else { return }
        let alert = NSAlert()
        alert.messageText = "重命名"
        alert.addButton(withTitle: "改好了")
        alert.addButton(withTitle: "取消")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        field.stringValue = b.title
        alert.accessoryView = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        d.renameBook(id, to: field.stringValue)
        d.syncCurrentBook()
        Vault.save(d)
        library?.reload(doc: d)
    }

    private func deleteBookFlow(_ id: String) {
        var d = Vault.load()
        guard let b = d.books.first(where: { $0.id == id }) else { return }
        let alert = NSAlert()
        alert.messageText = "删除「\(b.title)」？"
        alert.informativeText = "这本书里的 \(b.chapterCount) 章会一起删掉。删之前会自动存一份快照，可以从「从备份恢复」找回。"
        alert.addButton(withTitle: "删除")
        alert.addButton(withTitle: "取消")
        alert.alertStyle = .warning
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        Vault.snapshotNow(d)
        guard d.deleteBook(id) else { return }
        Vault.save(d)
        library?.reload(doc: d)
    }
}
