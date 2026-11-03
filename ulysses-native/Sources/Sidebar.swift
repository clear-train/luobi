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

extension EditorRoot: NSOutlineViewDataSource, NSOutlineViewDelegate, NSMenuDelegate {

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

    /// 当前搜索词（小写，去掉首尾空白）
    var searchQuery: String {
        searchField.stringValue.trimmingCharacters(in: .whitespaces).lowercased()
    }

    /// 在这篇文稿里找第一个命中的位置（标题优先，其次正文）
    func matchRange(in sheet: Sheet) -> NSRange? {
        let q = searchQuery
        guard !q.isEmpty else { return nil }
        let title = sheet.title as NSString
        let hitTitle = title.range(of: q, options: .caseInsensitive)
        if hitTitle.location != NSNotFound { return nil }   // 标题命中就不用跳正文
        let content = sheet.content as NSString
        let hit = content.range(of: q, options: .caseInsensitive)
        return hit.location == NSNotFound ? nil : hit
    }

    /// 搜索时显示的一行上下文：命中词前后各留一点字，换行压成空格
    func searchSnippet(for sheet: Sheet) -> NSAttributedString {
        let q = searchQuery
        let content = sheet.content.replacingOccurrences(of: "\n", with: " ")
        let ns = content as NSString
        let hit = ns.range(of: q, options: .caseInsensitive)
        let body: String
        if hit.location == NSNotFound {
            body = String(content.prefix(60))    // 只命中标题时，给个开头当预览
        } else {
            let start = max(0, hit.location - 18)
            let end = min(ns.length, hit.location + hit.length + 24)
            var piece = ns.substring(with: NSRange(location: start, length: end - start))
            if start > 0 { piece = "…" + piece }
            if end < ns.length { piece += "…" }
            body = piece
        }
        let attr = NSMutableAttributedString(
            string: body,
            attributes: [.font: NSFont.systemFont(ofSize: 11),
                         .foregroundColor: NSColor.secondaryLabelColor])
        // 把命中词标出来，扫一眼就知道为什么这篇被搜出来
        if hit.location != NSNotFound, hit.length > 0 {
            let shown = attr.string as NSString
            let r = shown.range(of: q, options: .caseInsensitive)
            if r.location != NSNotFound {
                attr.addAttributes([.foregroundColor: NSColor.labelColor,
                                    .backgroundColor: NSColor.selectedTextBackgroundColor.withAlphaComponent(0.35)],
                                   range: r)
            }
        }
        return attr
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

    func outlineView(_ outlineView: NSOutlineView, heightOfRowByItem item: Any) -> CGFloat {
        isSearching ? 46 : 28
    }

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let it = item as? SideItem else { return nil }

        // 搜索态用两行单元格：标题 + 命中片段
        if isSearching, case .sheet(let s) = it.kind {
            return searchCell(in: outlineView, sheet: s)
        }

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

    private func searchCell(in outlineView: NSOutlineView, sheet s: Sheet) -> NSView {
        let cellID = NSUserInterfaceItemIdentifier("searchCell")
        let cell: NSTableCellView
        var titleLabel: NSTextField
        var snippetLabel: NSTextField
        if let reuse = outlineView.makeView(withIdentifier: cellID, owner: nil) as? NSTableCellView,
           let t = reuse.viewWithTag(101) as? NSTextField,
           let n = reuse.viewWithTag(102) as? NSTextField {
            cell = reuse
            titleLabel = t
            snippetLabel = n
        } else {
            cell = NSTableCellView()
            cell.identifier = cellID
            titleLabel = NSTextField(labelWithString: "")
            titleLabel.tag = 101
            titleLabel.lineBreakMode = .byTruncatingTail
            titleLabel.translatesAutoresizingMaskIntoConstraints = false
            snippetLabel = NSTextField(labelWithString: "")
            snippetLabel.tag = 102
            snippetLabel.lineBreakMode = .byTruncatingTail
            snippetLabel.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(titleLabel)
            cell.addSubview(snippetLabel)
            cell.textField = titleLabel
            NSLayoutConstraint.activate([
                titleLabel.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 6),
                titleLabel.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -8),
                titleLabel.topAnchor.constraint(equalTo: cell.topAnchor, constant: 6),
                snippetLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
                snippetLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
                snippetLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 1),
            ])
        }
        let isActive = s.id == doc.activeId
        titleLabel.stringValue = s.title.isEmpty ? "未命名" : s.title
        titleLabel.font = NSFont.systemFont(ofSize: 12.5, weight: isActive ? .semibold : .regular)
        titleLabel.textColor = isActive ? .labelColor : .labelColor
        snippetLabel.attributedStringValue = searchSnippet(for: s)
        return cell
    }

    func outlineView(_ outlineView: NSOutlineView, shouldSelectItem item: Any) -> Bool {
        guard let it = item as? SideItem else { return false }
        // 点分组 = 展开/收起，不改变当前文稿
        if it.isFolder {
            animateFolder(it, open: !outlineView.isItemExpanded(it))
            return false
        }
        return true
    }

    func outlineViewSelectionDidChange(_ notification: Notification) {
        guard !updatingTable else { return }
        let row = table.selectedRow
        guard row >= 0, let it = table.item(atRow: row) as? SideItem, let s = it.sheet else { return }
        let wasSearching = isSearching
        let pending = wasSearching ? matchRange(in: s) : nil
        if s.id != doc.activeId { switchTo(s.id) }
        if let r = pending { jump(to: r) }
    }

    /// 把光标带到命中处，并让它落到屏幕中间
    func jump(to range: NSRange) {
        guard range.location != NSNotFound, range.location <= (textView.string as NSString).length else { return }
        textView.setSelectedRange(range)
        textView.scrollRangeToVisible(range)
        textView.centerSelectionInVisibleArea(nil)
        window?.makeFirstResponder(textView)
    }

    func outlineViewItemDidExpand(_ notification: Notification) {
        guard let it = notification.userInfo?["NSObject"] as? SideItem else { return }
        setExpanded(it.id, true)
    }

    func outlineViewItemDidCollapse(_ notification: Notification) {
        guard let it = notification.userInfo?["NSObject"] as? SideItem else { return }
        setExpanded(it.id, false)
    }

    /// 展开/收起带一点动画，像抽屉被拉开，而不是"啪"地多出几行
    func animateFolder(_ it: SideItem, open: Bool) {
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.18
            ctx.allowsImplicitAnimation = true
            if open { table.expandItem(it) } else { table.collapseItem(it) }
            table.layoutSubtreeIfNeeded()
        }, completionHandler: nil)
        setExpanded(it.id, open)
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
        _ = i
        // 落点决定两件事：归到哪个分组 + 插在谁前面
        var target: String? = nil
        var anchor: String? = nil
        if let it = item as? SideItem {
            if let f = it.folder {
                target = f.id
                // 落在分组内部第 index 个孩子之前；只把文稿当作锚点
                let kids = childItems(of: it)
                if index < kids.count, let s = kids[index].sheet { anchor = s.id }
            } else if let s = it.sheet {
                target = s.folderId
                anchor = s.id
            }
        } else {
            // 拖到空白处 = 放到最外层末尾
            let roots = rootItems()
            if index < roots.count, let s = roots[index].sheet { anchor = s.id }
        }
        reorder(str, toFolder: target, before: anchor)
        persistNow()
        refreshTable()
        if let f = target { expandFolder(f) }
        return true
    }

    /// 把一篇文稿挪到某分组内、某篇之前（anchor 为 nil 则放到该组末尾）。
    /// 顺序就是 doc.sheets 里的顺序，所以这里直接重排整个数组。
    func reorder(_ draggedId: String, toFolder folderId: String?, before anchorId: String?) {
        guard let di = doc.sheets.firstIndex(where: { $0.id == draggedId }) else { return }
        doc.sheets[di].folderId = folderId

        var members = doc.sheets.filter { $0.folderId == folderId }.map { $0.id }
        members.removeAll { $0 == draggedId }
        let insertAt: Int
        if let a = anchorId, let k = members.firstIndex(of: a) {
            insertAt = k
        } else {
            insertAt = members.count
        }
        members.insert(draggedId, at: min(insertAt, members.count))

        var queue = members
        var out: [Sheet] = []
        for s in doc.sheets {
            if s.folderId == folderId {
                guard !queue.isEmpty else { continue }
                let id = queue.removeFirst()
                if let src = doc.sheets.first(where: { $0.id == id }) { out.append(src) }
            } else {
                out.append(s)
            }
        }
        doc.sheets = out
    }

    /// 右键「上移 / 下移」：不想拖的时候也能调顺序
    @objc func moveSheetUp(_ sender: Any?) { nudgeSelected(by: -1) }
    @objc func moveSheetDown(_ sender: Any?) { nudgeSelected(by: 1) }

    private func nudgeSelected(by delta: Int) {
        guard let it = contextSideItem(), let s = it.sheet,
              let idx = doc.sheets.firstIndex(where: { $0.id == s.id }) else { return }
        let siblings = doc.sheets.enumerated().filter { $0.element.folderId == s.folderId }.map { $0.offset }
        guard let pos = siblings.firstIndex(of: idx) else { return }
        let targetPos = pos + delta
        guard targetPos >= 0, targetPos < siblings.count else { return }
        let other = siblings[targetPos]
        // 直接在数组里交换两篇的位置
        doc.sheets.swapAt(idx, other)
        persistNow()
        refreshTable()
        if let r = row(forID: s.id) { table.selectRowIndexes(IndexSet(integer: r), byExtendingSelection: false) }
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
        m.delegate = self
        m.addItem(withTitle: "新建文稿", action: #selector(addSheet(_:)), keyEquivalent: "")
        m.addItem(withTitle: "新建分组", action: #selector(addFolder(_:)), keyEquivalent: "")
        m.addItem(.separator())
        m.addItem(withTitle: "在此分组新建文稿", action: #selector(addSheetHere(_:)), keyEquivalent: "")
        let move = NSMenuItem(title: "移动到分组", action: nil, keyEquivalent: "")
        move.submenu = NSMenu()
        m.addItem(move)
        m.addItem(.separator())
        m.addItem(withTitle: "上移一位", action: #selector(moveSheetUp(_:)), keyEquivalent: "")
        m.addItem(withTitle: "下移一位", action: #selector(moveSheetDown(_:)), keyEquivalent: "")
        m.addItem(withTitle: "重命名…", action: #selector(renameSelected(_:)), keyEquivalent: "")
        m.addItem(withTitle: "删除", action: #selector(deleteSelected(_:)), keyEquivalent: "")
        for it in m.items where it.action != nil { it.target = self }
        return m
    }

    /// 菜单弹出前按点中的对象裁剪可用项，避免"点了没反应"
    func menuNeedsUpdate(_ menu: NSMenu) {
        let it = contextSideItem()
        let isFolder = it?.isFolder ?? false
        for item in menu.items {
            switch item.title {
            case "在此分组新建文稿":
                item.isHidden = !isFolder
            case "移动到分组":
                item.isHidden = it?.sheet == nil
                if let sub = item.submenu, let cur = it?.sheet {
                    sub.removeAllItems()
                    let root = NSMenuItem(title: "最外层（不归任何分组）", action: #selector(moveSheetToMenu(_:)), keyEquivalent: "")
                    root.target = self
                    root.representedObject = NSNull()
                    sub.addItem(root)
                    if !doc.folders.isEmpty { sub.addItem(.separator()) }
                    for f in allFoldersSorted() {
                        let mi = NSMenuItem(title: folderPath(f.id), action: #selector(moveSheetToMenu(_:)), keyEquivalent: "")
                        mi.target = self
                        mi.representedObject = f.id
                        mi.state = (cur.folderId == f.id) ? .on : .off
                        sub.addItem(mi)
                    }
                }
            case "上移一位", "下移一位":
                item.isHidden = (it?.sheet == nil)
            case "重命名…", "删除":
                item.isHidden = (it == nil)
            default:
                break
            }
        }
    }

    /// 深层分组按"小说 / 第一卷"这种路径排，方便在子菜单里认
    func allFoldersSorted() -> [Folder] {
        var out: [Folder] = []
        func walk(_ parent: String?) {
            for f in doc.folders.filter({ $0.parentId == parent }) {
                out.append(f)
                walk(f.id)
            }
        }
        walk(nil)
        return out
    }

    func folderPath(_ id: String) -> String {
        var parts: [String] = []
        var cur: String? = id
        var guardCount = 0
        while let c = cur, guardCount < 32, let f = doc.folders.first(where: { $0.id == c }) {
            parts.insert(f.name, at: 0)
            cur = f.parentId
            guardCount += 1
        }
        if parts.count > 1 { parts[0] = parts[0] + " /" }
        return parts.joined(separator: " ")
    }

    /// 右键「在此分组新建文稿」
    @objc func addSheetHere(_ sender: Any?) {
        var folder: String? = nil
        if let it = contextSideItem(), let f = it.folder {
            folder = f.id
            animateFolder(it, open: true)
        }
        var t = "未命名"
        var n = 2
        while doc.sheets.contains(where: { $0.title == t }) { t = "未命名 \(n)"; n += 1 }
        let s = Sheet(id: UUID().uuidString, title: t, content: "", folderId: folder)
        doc.sheets.append(s)
        switchTo(s.id)
    }

    /// 右键「移动到分组」里的具体一项
    @objc func moveSheetToMenu(_ sender: NSMenuItem) {
        guard let it = contextSideItem(), let s = it.sheet,
              let i = doc.sheets.firstIndex(where: { $0.id == s.id }) else { return }
        var target: String? = nil
        if let raw = sender.representedObject as? String { target = raw }
        doc.sheets[i].folderId = target
        persistNow()
        refreshTable()
        if let f = target, let folderRow = row(forID: f), let folderItem = table.item(atRow: folderRow) as? SideItem {
            animateFolder(folderItem, open: true)
            if let r = row(forID: s.id) { table.selectRowIndexes(IndexSet(integer: r), byExtendingSelection: false) }
        }
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
