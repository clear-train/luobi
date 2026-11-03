import AppKit

// MARK: - 侧栏：多篇文稿列表 + 搜索过滤

extension EditorRoot {
    var filtered: [Sheet] {
        let q = searchField.stringValue.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return doc.sheets }
        return doc.sheets.filter {
            $0.title.lowercased().contains(q) || $0.content.lowercased().contains(q)
        }
    }

    func refreshTable() {
        updatingTable = true
        table.reloadData()
        if let row = filtered.firstIndex(where: { $0.id == doc.activeId }) {
            table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            table.scrollRowToVisible(row)
        }
        updatingTable = false
    }

    func numberOfRows(in tableView: NSTableView) -> Int { filtered.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let cellID = NSUserInterfaceItemIdentifier("cell")
        let tf = (tableView.makeView(withIdentifier: cellID, owner: nil) as? NSTextField)
            ?? {
                let f = NSTextField(labelWithString: "")
                f.identifier = cellID
                f.font = NSFont.systemFont(ofSize: 13)
                f.lineBreakMode = .byTruncatingTail
                return f
            }()
        let s = filtered[row]
        tf.stringValue = s.title.isEmpty ? "未命名" : s.title
        tf.textColor = s.id == doc.activeId ? .labelColor : .secondaryLabelColor
        return tf
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard !updatingTable else { return }
        let row = table.selectedRow
        guard row >= 0, row < filtered.count else { return }
        let id = filtered[row].id
        guard id != doc.activeId else { return }
        switchTo(id)
    }
}
