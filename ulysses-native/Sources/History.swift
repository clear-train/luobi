import AppKit

// MARK: - 单篇版本历史
//
// 全库快照是"整本"的后悔药（Backups/），解决不了"第三章昨天长什么样"。
// 这里给每一篇单独留版本：正文改过就存一份纯文本，按时间倒序，最多 40 份。
//
// 为什么存成独立的 .md 文件而不是塞进 state.json：
//   1. state.json 是要秒开的，塞进几千份历史会越开越慢；
//   2. 纯文本文件用访达就能看、能拷、能 diff，出问题时不用求 App。

struct HistoryEntry {
    let url: URL
    let date: Date
    let words: Int
    var title: String {
        let f = DateFormatter()
        f.dateFormat = "MM-dd HH:mm"
        return "\(f.string(from: date)) · \(words) 字"
    }
}

enum SheetHistory {

    static var root: URL { Vault.dir.appendingPathComponent("History", isDirectory: true) }

    static func dir(for sheetId: String) -> URL {
        root.appendingPathComponent(sheetId, isDirectory: true)
    }

    /// 存一份版本。内容与最新一份相同则跳过（自动保存很频繁，不能每次都写）
    @discardableResult
    static func record(sheet: Sheet, force: Bool = false) -> URL? {
        let body = sheet.content
        guard !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let d = dir(for: sheet.id)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        let existing = list(sheetId: sheet.id)
        if !force, let latest = existing.first {
            if let old = try? String(contentsOf: latest.url, encoding: .utf8), old == body { return nil }
        }
        let stamp = Int(Date().timeIntervalSince1970)
        var url = d.appendingPathComponent("\(stamp).md")
        var n = 1
        while FileManager.default.fileExists(atPath: url.path) {
            url = d.appendingPathComponent("\(stamp)-\(n).md"); n += 1
        }
        do {
            try body.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            return nil
        }
        prune(sheetId: sheet.id)
        return url
    }

    static func list(sheetId: String) -> [HistoryEntry] {
        let d = dir(for: sheetId)
        guard let files = try? FileManager.default.contentsOfDirectory(at: d, includingPropertiesForKeys: [.contentModificationDateKey]) else { return [] }
        var out: [HistoryEntry] = []
        for f in files where f.pathExtension == "md" {
            let date = (try? f.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date.distantPast
            let body = (try? String(contentsOf: f, encoding: .utf8)) ?? ""
            out.append(HistoryEntry(url: f, date: date, words: statCJK(body) + statLatin(body)))
        }
        return out.sorted { $0.date > $1.date }
    }

    static func load(_ entry: HistoryEntry) -> String? {
        try? String(contentsOf: entry.url, encoding: .utf8)
    }

    /// 每篇最多留 40 份，超了就删最旧的
    static func prune(sheetId: String, keep: Int = 40) {
        let all = list(sheetId: sheetId)
        guard all.count > keep else { return }
        for e in all.dropFirst(keep) { try? FileManager.default.removeItem(at: e.url) }
    }

    static func removeAll(sheetId: String) {
        try? FileManager.default.removeItem(at: dir(for: sheetId))
    }

    static func remove(_ entry: HistoryEntry) {
        try? FileManager.default.removeItem(at: entry.url)
    }
}

extension EditorRoot {

    /// 侧栏右键「历史版本…」/ 视图菜单
    @objc func showHistoryPanel(_ sender: Any?) {
        guard let sheet = contextSideItem()?.sheet ?? doc.sheet(id: doc.activeId) else { return }
        let preset = ThemePresets.preset(doc.theme)
        let entries = SheetHistory.list(sheetId: sheet.id)

        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 660, height: 470),
                            styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        panel.title = "历史版本 · \(sheet.title)"
        if ThemePresets.preset(doc.theme).isDark { panel.appearance = NSAppearance(named: .darkAqua) }
        panel.isReleasedWhenClosed = false
        panel.backgroundColor = preset.bg

        let host = NSView()
        host.wantsLayer = true
        host.layer?.backgroundColor = preset.bg.cgColor

        let hint = NSTextField(labelWithString: entries.isEmpty
                               ? "这一篇还没有历史版本。改动正文并等自动保存后，就会开始记录（每篇最多 40 份）。"
                               : "共 \(entries.count) 个版本 · 每次改动自动存一份 · 最多保留 40 份")
        hint.font = NSFont.systemFont(ofSize: 11)
        hint.textColor = preset.text.withAlphaComponent(0.55)
        hint.translatesAutoresizingMaskIntoConstraints = false

        let table = NSTableView()
        table.headerView = nil
        table.rowHeight = 26
        table.backgroundColor = .clear
        table.selectionHighlightStyle = .regular
        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("v"))
        col.width = 170
        table.addTableColumn(col)
        let listScroll = NSScrollView()
        listScroll.documentView = table
        listScroll.hasVerticalScroller = true
        listScroll.drawsBackground = false
        listScroll.translatesAutoresizingMaskIntoConstraints = false

        let preview = NSTextView()
        preview.isEditable = false
        preview.drawsBackground = false
        preview.font = NSFont(name: "STSongti-SC-Regular", size: 13) ?? NSFont.systemFont(ofSize: 13)
        preview.textColor = preset.text.withAlphaComponent(0.85)
        preview.textContainerInset = NSSize(width: 10, height: 10)
        let prevScroll = NSScrollView()
        prevScroll.documentView = preview
        prevScroll.hasVerticalScroller = true
        prevScroll.drawsBackground = false
        prevScroll.borderType = .noBorder
        prevScroll.translatesAutoresizingMaskIntoConstraints = false

        let restore = NSButton(title: "恢复这个版本", target: nil, action: nil)
        let del = NSButton(title: "删除这个版本", target: nil, action: nil)
        let close = NSButton(title: "关闭", target: nil, action: nil)
        for b in [restore, del, close] { b.bezelStyle = .rounded; b.translatesAutoresizingMaskIntoConstraints = false }

        let helper = ReplaceHelper()
        var selection: HistoryEntry? = entries.first

        func loadPreview() {
            guard let e = selection else { preview.string = ""; return }
            preview.string = SheetHistory.load(e) ?? ""
            preview.scrollToBeginningOfDocument(nil)
        }

        final class HistoryDS: NSObject, NSTableViewDataSource, NSTableViewDelegate {
            var entries: [HistoryEntry] = []
            var onSelect: ((HistoryEntry) -> Void)?
            var textColor: NSColor = .labelColor
            func numberOfRows(in tableView: NSTableView) -> Int { entries.count }
            func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
                let id = NSUserInterfaceItemIdentifier("cell")
                let cell: NSTextField
                if let reused = tableView.makeView(withIdentifier: id, owner: nil) as? NSTextField {
                    cell = reused
                } else {
                    cell = NSTextField(labelWithString: "")
                    cell.identifier = id
                    cell.font = NSFont.systemFont(ofSize: 11.5)
                    cell.lineBreakMode = .byTruncatingTail
                }
                cell.textColor = textColor
                cell.stringValue = entries[row].title
                return cell
            }
            func tableViewSelectionDidChange(_ notification: Notification) {
                guard let t = notification.object as? NSTableView, t.selectedRow >= 0, t.selectedRow < entries.count else { return }
                onSelect?(entries[t.selectedRow])
            }
        }
        let ds = HistoryDS()
        ds.entries = entries
        ds.textColor = preset.text
        ds.onSelect = { e in selection = e; loadPreview() }
        table.dataSource = ds
        table.delegate = ds
        objc_setAssociatedObject(panel, Unmanaged.passUnretained(panel).toOpaque(), ds, .OBJC_ASSOCIATION_RETAIN)
        if !entries.isEmpty {
            table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
            loadPreview()
        }

        restore.target = helper
        restore.action = Selector(("performReplace:"))
        restore.isEnabled = !entries.isEmpty
        helper.onPerform = { [weak self, weak panel] in
            guard let self = self, let e = selection, let body = SheetHistory.load(e) else { return }
            guard let idx = self.doc.sheets.firstIndex(where: { $0.id == sheet.id }) else { return }
            // 恢复前把「现在这一版」也存下来，避免恢复成了新的后悔
            SheetHistory.record(sheet: self.doc.sheets[idx], force: true)
            self.doc.sheets[idx].content = body
            self.doc.sheets[idx].updatedAt = Date().timeIntervalSince1970
            self.switchTo(sheet.id)
            self.persistNow()
            self.startupNote = "已恢复到 \(e.title)"
            self.refreshBar()
            panel?.close()
        }
        del.target = helper
        del.action = Selector(("performDeleteHistory:"))
        helper.onDeleteHistory = { [weak panel] in
            guard let e = selection else { return }
            SheetHistory.remove(e)
            panel?.close()
        }
        close.target = helper
        close.action = Selector(("performCancel:"))
        helper.onCancel = { [weak panel] in panel?.close() }
        objc_setAssociatedObject(panel, Unmanaged.passUnretained(panel).toOpaque(), helper, .OBJC_ASSOCIATION_RETAIN)

        for v in [hint, listScroll, prevScroll, restore, del, close] { host.addSubview(v) }
        NSLayoutConstraint.activate([
            hint.topAnchor.constraint(equalTo: host.topAnchor, constant: 14),
            hint.leadingAnchor.constraint(equalTo: host.leadingAnchor, constant: 16),
            hint.trailingAnchor.constraint(equalTo: host.trailingAnchor, constant: -16),

            listScroll.topAnchor.constraint(equalTo: hint.bottomAnchor, constant: 10),
            listScroll.leadingAnchor.constraint(equalTo: host.leadingAnchor, constant: 16),
            listScroll.widthAnchor.constraint(equalToConstant: 180),
            listScroll.bottomAnchor.constraint(equalTo: restore.topAnchor, constant: -12),

            prevScroll.topAnchor.constraint(equalTo: listScroll.topAnchor),
            prevScroll.leadingAnchor.constraint(equalTo: listScroll.trailingAnchor, constant: 12),
            prevScroll.trailingAnchor.constraint(equalTo: host.trailingAnchor, constant: -16),
            prevScroll.bottomAnchor.constraint(equalTo: listScroll.bottomAnchor),

            close.trailingAnchor.constraint(equalTo: host.trailingAnchor, constant: -16),
            close.bottomAnchor.constraint(equalTo: host.bottomAnchor, constant: -14),
            restore.trailingAnchor.constraint(equalTo: close.leadingAnchor, constant: -10),
            restore.centerYAnchor.constraint(equalTo: close.centerYAnchor),
            del.leadingAnchor.constraint(equalTo: host.leadingAnchor, constant: 16),
            del.centerYAnchor.constraint(equalTo: close.centerYAnchor),
        ])
        panel.contentView = host
        if let win = window { win.beginSheet(panel) { _ in } } else { panel.makeKeyAndOrderFront(nil) }
    }
}
