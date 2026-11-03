import AppKit

// MARK: - 侧栏：分组树 + 文稿 + 搜索 + 拖拽归档 + 右键菜单

/// 树里的一个节点：要么是分组，要么是一篇文稿
final class SideItem: NSObject {
    enum Kind {
        case folder(Folder)
        case sheet(Sheet)
    }
    let kind: Kind

    init(_ kind: Kind) { self.kind = kind }

    var id: String {
        switch kind {
        case .folder(let f): return f.id
        case .sheet(let s): return s.id
        }
    }

    var isFolder: Bool {
        if case .folder = kind { return true }
        return false
    }

    var sheet: Sheet? {
        if case .sheet(let s) = kind { return s }
        return nil
    }

    var folder: Folder? {
        if case .folder(let f) = kind { return f }
        return nil
    }
}

extension EditorRoot: NSOutlineViewDataSource, NSOutlineViewDelegate {

    // MARK: 数据

    /// 搜索框有内容时，侧栏退化成「扁平搜索结果」，不显示分组
    var isSearching: Bool {
        !searchField.stringValue.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var filtered: [Sheet] {
        let q = searchField.stringValue.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return doc.sheets }
        return doc.sheets.filter {
            $0.title.lowercased().contains(q) || $0.content.lowercased().contains(q)
        }
    }

    func rootItems() -> [SideItem] {
        if isSearching { return filtered.map { SideItem(.sheet($0)) } }
        var out: [SideItem] = []
        for f in doc.folders where f.parentId == nil {
            out.append(SideItem(.folder(f)))
        }
        for s in doc.sheets where s.folderId == nil {
            out.append(SideItem(.sheet(s)))
        }
        return out
    }

    func childItems(of item: SideItem) -> [SideItem] {
        guard let f = item.folder else { return [] }
        var out: [SideItem] = []
        for cf in doc.folders where cf.parentId == f.id {
            out.append(SideItem(.folder(cf)))
        }
        for s in doc.sheets where s.folderId == f.id {
            out.append(SideItem(.sheet(s)))
        }
        return out
    }

    func items(at parent: Any?) -> [SideItem] {
        guard let item = parent as? SideItem else { return rootItems() }
        return childItems(of: item)
    }

    // MARK: 刷新

    func refreshTable() {
        updatingTable = true
        let keepExpanded = Set(doc.folders.filter { $0.expanded != false }.map { $0.id })
        table.reloadData()

        if !isSearching {
            var row = 0
            while row < table.numberOfRows {
                if let it = table.item(atRow: row) as? SideItem,
                   let f = it.folder, keepExpanded.contains(f.id) {
                    table.expandItem(it)
                }
                row += 1
            }
        }
        if let row = row(forID: doc.activeId) {
            table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            table.scrollRowToVisible(row)
        }
        updatingTable = false
    }

    private func row(forID id: String) -> Int? {
        for r in 0..<table.numberOfRows {
            if let it = table.item(atRow: r) as? SideItem, it.id == id { return r }
        }
        return nil
    }

    // MARK: NSOutlineViewDataSource

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        items(at: item).count
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        items(at: item)[index]
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        guard let it = item as? SideItem else { return false }
        return it.isFolder && !childItems(of: it).isEmpty
    }

    // MARK: NSOutlineViewDelegate

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let it = item as? SideItem else { return nil }
        let cellID = NSUserInterfaceItemIdentifier("cell")
        let cell: NSTableCellView
        if let reuse = outlineView.makeView(withIdentifier: cellID, owner: nil) as? NSTableCellView {
            cell = reuse
        } else {
            cell = NSTableCellView()
            cell.identifier = cellID
            let tf = NSTextField(labelWithString: "")
            tf.translatesAutoresizingMaskIntoConstraints = false
            tf.lineBreakMode = .byTruncatingTail
            tf.alignment = .left
            cell.addSubview(tf)
            cell.textField = tf
            NSLayoutConstraint.activate([
                tf.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 6),
                tf.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -8),
                tf.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            ])
        }
        guard let tf = cell.textField else { return cell }
        tf.alignment = .left

        switch it.kind {
        case .folder(let f):
            // 分组名 + 灰色计数（「小说 2」比「小说(2)」安静）
            let n = doc.sheets(in: f.id).count
            let attr = NSMutableAttributedString(
                string: f.name,
                attributes: [.font: NSFont.systemFont(ofSize: 12.5, weight: .semibold),
                             .foregroundColor: NSColor.labelColor])
            if n > 0 {
                attr.append(NSAttributedString(
                    string: "  \(n)",
                    attributes: [.font: NSFont.systemFont(ofSize: 11),
                                 .foregroundColor: NSColor.tertiaryLabelColor]))
            }
            tf.attributedStringValue = attr
        case .sheet(let s):
            tf.stringValue = s.title.isEmpty ? "未命名" : s.title
            tf.font = NSFont.systemFont(ofSize: 13)
            tf.textColor = s.id == doc.activeId ? .labelColor : .secondaryLabelColor
        }
        return cell
    }

    func outlineView(_ outlineView: NSOutlineView, shouldSelectItem item: Any) -> Bool {
        guard let it = item as? SideItem else { return false }
        // 点分组 = 展开/收起，不改变当前文稿
        if it.isFolder {
            if outlineView.isItemExpanded(it) {
                outlineView.collapseItem(it)
                setExpanded(it.id, false)
            } else {
                outlineView.expandItem(it)
                setExpanded(it.id, true)
            }
            return false
        }
        return true
    }

    func outlineViewSelectionDidChange(_ notification: Notification) {
        guard !updatingTable else { return }
        let row = table.selectedRow
        guard row >= 0, let it = table.item(atRow: row) as? SideItem, let s = it.sheet else { return }
        guard s.id != doc.activeId else { return }
        switchTo(s.id)
    }

    func outlineViewItemDidExpand(_ notification: Notification) {
        guard let it = notification.userInfo?["NSObject"] as? SideItem else { return }
        setExpanded(it.id, true)
    }

    func outlineViewItemDidCollapse(_ notification: Notification) {
        guard let it = notification.userInfo?["NSObject"] as? SideItem else { return }
        setExpanded(it.id, false)
    }

    private func setExpanded(_ id: String, _ open: Bool) {
        guard let i = doc.folders.firstIndex(where: { $0.id == id }) else { return }
        doc.folders[i].expanded = open
        persistNow()
    }

    // MARK: 拖拽：把文稿拖进分组（或拖回最外层）

    func outlineView(_ outlineView: NSOutlineView, pasteboardWriterForItem item: Any) -> NSPasteboardWriting? {
        guard !isSearching, let it = item as? SideItem, let s = it.sheet else { return nil }
        let pb = NSPasteboardItem()
        pb.setString(s.id, forType: NSPasteboard.PasteboardType("com.ulysses.sheet"))
        return pb
    }

    func outlineView(_ outlineView: NSOutlineView,
                     validateDrop info: NSDraggingInfo,
                     proposedItem item: Any?,
                     proposedChildIndex index: Int) -> NSDragOperation {
        guard !isSearching else { return [] }
        if item == nil { return .move }                     // 拖到空白处 = 移到最外层
        if let it = item as? SideItem, it.isFolder { return .move }
        return []
    }

    func outlineView(_ outlineView: NSOutlineView,
                     acceptDrop info: NSDraggingInfo,
                     item: Any?,
                     childIndex index: Int) -> Bool {
        guard let str = info.draggingPasteboard.string(forType: NSPasteboard.PasteboardType("com.ulysses.sheet")),
              let i = doc.sheets.firstIndex(where: { $0.id == str }) else { return false }
        var target: String? = nil
        if let it = item as? SideItem, let f = it.folder { target = f.id }
        doc.sheets[i].folderId = target
        persistNow()
        refreshTable()
        if let f = target { expandFolder(f) }
        return true
    }

    private func expandFolder(_ id: String) {
        if let i = row(forID: id), let it = table.item(atRow: i) as? SideItem {
            table.expandItem(it)
            setExpanded(id, true)
        }
    }

    // MARK: 右键菜单

    func makeSidebarMenu() -> NSMenu {
        let m = NSMenu()
        m.addItem(withTitle: "新建文稿", action: #selector(addSheet(_:)), keyEquivalent: "")
        m.addItem(withTitle: "新建分组", action: #selector(addFolder(_:)), keyEquivalent: "")
        m.addItem(.separator())
        m.addItem(withTitle: "重命名…", action: #selector(renameSelected(_:)), keyEquivalent: "")
        m.addItem(withTitle: "删除", action: #selector(deleteSelected(_:)), keyEquivalent: "")
        for it in m.items { it.target = self }
        return m
    }

    // MARK: 分组 / 重命名 / 删除

    @objc func addFolder(_ sender: Any?) {
        var parent: String? = nil
        let row = table.clickedRow >= 0 ? table.clickedRow : table.selectedRow
        if row >= 0, let it = table.item(atRow: row) as? SideItem, let f = it.folder {
            parent = f.id
            table.expandItem(it)
        }
        var name = "新分组"
        var n = 2
        while doc.folders.contains(where: { $0.name == name && $0.parentId == parent }) {
            name = "新分组 \(n)"
            n += 1
        }
        let f = Folder(id: UUID().uuidString, name: name, parentId: parent)
        doc.folders.append(f)
        persistNow()
        refreshTable()
        renameFolder(f.id)   // 建完直接让你起名，省一次右键
    }

    private func contextSideItem() -> SideItem? {
        let row = table.clickedRow >= 0 ? table.clickedRow : table.selectedRow
        guard row >= 0 else { return nil }
        return table.item(atRow: row) as? SideItem
    }

    @objc func renameSelected(_ sender: Any?) {
        guard let it = contextSideItem() else { return }
        if let f = it.folder {
            renameFolder(f.id)
        } else if let s = it.sheet {
            renameSheet(s.id)
        }
    }

    func renameFolder(_ id: String) {
        guard let i = doc.folders.firstIndex(where: { $0.id == id }) else { return }
        let alert = NSAlert()
        alert.messageText = "分组名称"
        alert.informativeText = "改个好认的名字，比如「童年」「2024 年」「素材」。"
        alert.addButton(withTitle: "确定")
        alert.addButton(withTitle: "取消")
        let tf = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        tf.stringValue = doc.folders[i].name
        alert.accessoryView = tf
        alert.window.initialFirstResponder = tf
        if alert.runModal() == .alertFirstButtonReturn {
            let v = tf.stringValue.trimmingCharacters(in: .whitespaces)
            if !v.isEmpty { doc.folders[i].name = v }
            persistNow()
            refreshTable()
        }
    }

    func renameSheet(_ id: String) {
        guard let i = doc.sheets.firstIndex(where: { $0.id == id }) else { return }
        let alert = NSAlert()
        alert.messageText = "文稿标题"
        alert.addButton(withTitle: "确定")
        alert.addButton(withTitle: "取消")
        let tf = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        tf.stringValue = doc.sheets[i].title
        alert.accessoryView = tf
        alert.window.initialFirstResponder = tf
        if alert.runModal() == .alertFirstButtonReturn {
            let v = tf.stringValue.trimmingCharacters(in: .whitespaces)
            doc.sheets[i].title = v.isEmpty ? "未命名" : v
            if id == doc.activeId { titleInput.stringValue = doc.sheets[i].title }
            persistNow()
            refreshTable()
        }
    }

    @objc func deleteSelected(_ sender: Any?) {
        guard let it = contextSideItem() else { return }
        if let f = it.folder {
            deleteFolder(f.id)
        } else if let s = it.sheet {
            deleteSheet(s.id)
        }
    }

    func deleteSheet(_ id: String) {
        guard let i = doc.sheets.firstIndex(where: { $0.id == id }) else { return }
        if doc.sheets.count <= 1 {
            let a = NSAlert()
            a.messageText = "这是最后一篇了"
            a.informativeText = "留着它吧，删掉就没有纸可写了。"
            a.addButton(withTitle: "好")
            a.runModal()
            return
        }
        let alert = NSAlert()
        alert.messageText = "删除「\(doc.sheets[i].title.isEmpty ? "未命名" : doc.sheets[i].title)」？"
        alert.informativeText = "删除后无法恢复。想留个底，先用「导出」存一份。"
        alert.addButton(withTitle: "删除")
        alert.addButton(withTitle: "取消")
        alert.alertStyle = .warning
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        doc.sheets.remove(at: i)
        if doc.activeId == id {
            let next = doc.sheets[min(i, doc.sheets.count - 1)]
            doc.activeId = next.id
            titleInput.stringValue = next.title
            textView.string = next.content
            applyMarkdownStyling()
        }
        persistNow()
        refreshTable()
    }

    func deleteFolder(_ id: String) {
        guard let f = doc.folder(id: id) else { return }
        var ids: [String] = []
        var stack = [id]
        while let cur = stack.popLast() {
            ids.append(cur)
            stack.append(contentsOf: doc.folders.filter { $0.parentId == cur }.map { $0.id })
        }
        let inside = doc.sheets.filter { s in ids.contains(s.folderId ?? "") }
        let alert = NSAlert()
        alert.messageText = "删除分组「\(f.name)」？"
        alert.informativeText = inside.isEmpty
            ? "这个分组是空的。"
            : "里面的 \(inside.count) 篇文稿不会被删除，会移到上一层。"
        alert.addButton(withTitle: "删除分组")
        alert.addButton(withTitle: "取消")
        alert.alertStyle = .warning
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        // 文稿上移一层（不会丢内容）
        let parent = f.parentId
        for i in doc.sheets.indices where ids.contains(doc.sheets[i].folderId ?? "") {
            doc.sheets[i].folderId = parent
        }
        doc.folders.removeAll { ids.contains($0.id) }
        persistNow()
        refreshTable()
    }
}
