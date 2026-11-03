import AppKit

// MARK: - 全库查找替换
//
// 写长篇最常干的一件事：把人名、地名、某个用词统一掉。
// 一个词改十几次还能忍，改八十次就会开始破坏一致性——
// 所以这个功能只有一条底线：**替换范围要说得清楚，替换结果要能撤回**。

enum ReplaceScope: Int {
    case currentSheet = 0   // 当前这一篇
    case currentFolder = 1  // 当前分组（含子分组）
    case all = 2            // 全部文稿
}

extension DocState {

    /// 找出范围内的文稿（人物卡不参与，避免把设定里的名字改坏）
    func sheets(in scope: ReplaceScope, activeId: String) -> [Sheet] {
        let active = sheet(id: activeId)
        switch scope {
        case .currentSheet:
            return active.map { [$0] } ?? []
        case .currentFolder:
            guard let f = active?.folderId else {
                return sheets.filter { $0.card == nil && $0.folderId == nil }
            }
            let ids = descendantFolderIds(of: f)
            return sheets.filter { $0.card == nil && $0.folderId.map { ids.contains($0) } == true }
        case .all:
            return sheets.filter { $0.card == nil }
        }
    }

    /// 某个分组的全部子孙分组 id（含自己）
    func descendantFolderIds(of root: String) -> Set<String> {
        var out: Set<String> = [root]
        var changed = true
        while changed {
            changed = false
            for f in folders where f.parentId.map({ out.contains($0) }) == true {
                if !out.contains(f.id) { out.insert(f.id); changed = true }
            }
        }
        return out
    }

    /// 统计会替换多少处（不修改数据）
    func countMatches(find: String, in sheets: [Sheet], caseSensitive: Bool) -> (occurrences: Int, sheets: Int) {
        guard !find.isEmpty else { return (0, 0) }
        let opts: NSString.CompareOptions = caseSensitive ? [] : [.caseInsensitive]
        var occ = 0, touched = 0
        for s in sheets {
            var n = 0
            let ns = s.content as NSString
            var from = 0
            while from < ns.length {
                let r = ns.range(of: find, options: opts, range: NSRange(location: from, length: ns.length - from))
                if r.location == NSNotFound { break }
                n += 1
                from = r.location + max(1, r.length)
            }
            if n > 0 { occ += n; touched += 1 }
        }
        return (occ, touched)
    }

    /// 执行替换（就地改 doc.sheets），返回替换处数与涉及篇数
    @discardableResult
    mutating func replaceAll(find: String, with replacement: String, in scopeSheets: [Sheet],
                             caseSensitive: Bool) -> (occurrences: Int, sheets: Int) {
        guard !find.isEmpty else { return (0, 0) }
        let ids = Set(scopeSheets.map { $0.id })
        let opts: NSString.CompareOptions = caseSensitive ? [] : [.caseInsensitive]
        var occ = 0, touched = 0
        for i in sheets.indices where ids.contains(sheets[i].id) {
            let src = sheets[i].content
            let ns = src as NSString
            let result = NSMutableString()
            var from = 0
            var n = 0
            while from < ns.length {
                let r = ns.range(of: find, options: opts, range: NSRange(location: from, length: ns.length - from))
                if r.location == NSNotFound { break }
                result.append(ns.substring(with: NSRange(location: from, length: r.location - from)))
                result.append(replacement)
                from = r.location + r.length
                n += 1
            }
            if n > 0 {
                result.append(ns.substring(from: from))
                sheets[i].content = result as String
                occ += n
                touched += 1
            }
        }
        return (occ, touched)
    }
}

extension EditorRoot {

    @objc func showReplacePanel(_ sender: Any?) {
        let preset = ThemePresets.preset(doc.theme)

        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 560, height: 248),
                            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        panel.title = "查找与替换"
        panel.isReleasedWhenClosed = false
        panel.backgroundColor = preset.bg

        let host = NSView()
        host.wantsLayer = true
        host.layer?.backgroundColor = preset.bg.cgColor

        func label(_ t: String, size: CGFloat = 12) -> NSTextField {
            let l = NSTextField(labelWithString: t)
            l.font = NSFont.systemFont(ofSize: size)
            l.textColor = preset.text.withAlphaComponent(0.75)
            l.translatesAutoresizingMaskIntoConstraints = false
            return l
        }

        let findLabel = label("查找")
        let findField = NSTextField()
        findField.placeholderString = "要查找的文字"
        findField.translatesAutoresizingMaskIntoConstraints = false

        let replLabel = label("替换为")
        let replField = NSTextField()
        replField.placeholderString = "留空＝删除匹配的文字"
        replField.translatesAutoresizingMaskIntoConstraints = false

        let caseBox = NSButton(checkboxWithTitle: "区分大小写", target: nil, action: nil)
        caseBox.state = .off
        caseBox.translatesAutoresizingMaskIntoConstraints = false

        let scopePopup = NSPopUpButton(frame: .zero, pullsDown: false)
        scopePopup.addItems(withTitles: ["仅当前这一篇", "当前分组（含子分组）", "全部文稿"])
        scopePopup.selectItem(at: 2)
        scopePopup.translatesAutoresizingMaskIntoConstraints = false

        let info = label("", size: 11)
        info.textColor = preset.text.withAlphaComponent(0.5)

        let doReplace = NSButton(title: "全部替换", target: nil, action: nil)
        doReplace.bezelStyle = .rounded
        doReplace.keyEquivalent = "\r"
        doReplace.translatesAutoresizingMaskIntoConstraints = false

        let cancel = NSButton(title: "取消", target: nil, action: nil)
        cancel.bezelStyle = .rounded
        cancel.keyEquivalent = "\u{1b}"
        cancel.translatesAutoresizingMaskIntoConstraints = false

        for v in [findLabel, findField, replLabel, replField, caseBox, scopePopup, info, doReplace, cancel] {
            host.addSubview(v)
        }
        NSLayoutConstraint.activate([
            findLabel.topAnchor.constraint(equalTo: host.topAnchor, constant: 20),
            findLabel.leadingAnchor.constraint(equalTo: host.leadingAnchor, constant: 20),
            findLabel.widthAnchor.constraint(equalToConstant: 60),

            findField.centerYAnchor.constraint(equalTo: findLabel.centerYAnchor),
            findField.leadingAnchor.constraint(equalTo: findLabel.trailingAnchor, constant: 8),
            findField.trailingAnchor.constraint(equalTo: host.trailingAnchor, constant: -20),

            replLabel.topAnchor.constraint(equalTo: findLabel.bottomAnchor, constant: 14),
            replLabel.leadingAnchor.constraint(equalTo: findLabel.leadingAnchor),
            replLabel.widthAnchor.constraint(equalToConstant: 60),

            replField.centerYAnchor.constraint(equalTo: replLabel.centerYAnchor),
            replField.leadingAnchor.constraint(equalTo: findField.leadingAnchor),
            replField.trailingAnchor.constraint(equalTo: findField.trailingAnchor),

            caseBox.topAnchor.constraint(equalTo: replField.bottomAnchor, constant: 16),
            caseBox.leadingAnchor.constraint(equalTo: findField.leadingAnchor),

            scopePopup.centerYAnchor.constraint(equalTo: caseBox.centerYAnchor),
            scopePopup.leadingAnchor.constraint(equalTo: caseBox.trailingAnchor, constant: 16),
            scopePopup.widthAnchor.constraint(equalToConstant: 190),

            info.topAnchor.constraint(equalTo: caseBox.bottomAnchor, constant: 14),
            info.leadingAnchor.constraint(equalTo: host.leadingAnchor, constant: 20),
            info.trailingAnchor.constraint(equalTo: host.trailingAnchor, constant: -20),

            doReplace.trailingAnchor.constraint(equalTo: host.trailingAnchor, constant: -20),
            doReplace.bottomAnchor.constraint(equalTo: host.bottomAnchor, constant: -16),
            cancel.trailingAnchor.constraint(equalTo: doReplace.leadingAnchor, constant: -10),
            cancel.centerYAnchor.constraint(equalTo: doReplace.centerYAnchor),
        ])

        func scope(_ raw: Int) -> ReplaceScope { ReplaceScope(rawValue: raw) ?? .all }

        func refreshInfo() {
            let find = findField.stringValue
            guard !find.isEmpty else { info.stringValue = "输入要查找的文字"; return }
            let list = doc.sheets(in: scope(scopePopup.indexOfSelectedItem), activeId: doc.activeId)
            let r = doc.countMatches(find: find, in: list, caseSensitive: caseBox.state == .on)
            info.stringValue = r.occurrences == 0
                ? "没有找到匹配"
                : "将替换 \(r.occurrences) 处，涉及 \(r.sheets) 篇"
        }
        refreshInfo()

        // 输入时实时更新「将替换 N 处」
        let o1 = NotificationCenter.default.addObserver(forName: NSControl.textDidChangeNotification,
                                                        object: findField, queue: .main) { _ in refreshInfo() }
        let o2 = NotificationCenter.default.addObserver(forName: NSControl.textDidChangeNotification,
                                                        object: replField, queue: .main) { _ in refreshInfo() }

        let helper = ReplaceHelper()
        doReplace.target = helper
        doReplace.action = Selector(("performReplace:"))
        helper.onPerform = { [weak self, weak panel] in
            guard let self = self else { return }
            let find = findField.stringValue
            guard !find.isEmpty else { return }
            let list = self.doc.sheets(in: scope(scopePopup.indexOfSelectedItem), activeId: self.doc.activeId)
            // 替换前先存一份快照：改错了能在「文件 → 从备份恢复」里找回
            Vault.snapshotNow(self.doc)
            let r = self.doc.replaceAll(find: find, with: replField.stringValue, in: list,
                                       caseSensitive: caseBox.state == .on)
            if let cur = self.doc.sheet(id: self.doc.activeId) {
                self.textView.string = cur.content
                self.applyMarkdownStyling()
            }
            self.refreshTable()
            self.persistNow()
            self.startupNote = r.occurrences > 0
                ? "已替换 \(r.occurrences) 处（\(r.sheets) 篇），替换前已自动备份"
                : "没有找到匹配，未做修改"
            self.refreshBar()
            panel?.close()
        }

        cancel.target = helper
        cancel.action = Selector(("performCancel:"))
        helper.onCancel = { [weak panel] in panel?.close() }

        // 面板关掉后把通知观察者撤掉，避免泄漏
        _ = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification,
                                                   object: panel, queue: .main) { _ in
            NotificationCenter.default.removeObserver(o1)
            NotificationCenter.default.removeObserver(o2)
        }

        // helper 要有强引用，否则按钮的 weak target 会先被释放
        objc_setAssociatedObject(panel, Unmanaged.passUnretained(panel).toOpaque(), helper, .OBJC_ASSOCIATION_RETAIN)

        panel.contentView = host
        if let win = window { win.beginSheet(panel) { _ in } } else { panel.makeKeyAndOrderFront(nil) }
        panel.makeFirstResponder(findField)
    }
}

/// 让按钮能执行闭包的小帮手（NSButton 的 target/action 只认对象方法）
final class ReplaceHelper: NSObject {
    var onPerform: (() -> Void)?
    var onCancel: (() -> Void)?
    var onDeleteHistory: (() -> Void)?
    @objc func performReplace(_ sender: Any?) { onPerform?() }
    @objc func performCancel(_ sender: Any?) { onCancel?() }
    @objc func performDeleteHistory(_ sender: Any?) { onDeleteHistory?() }
}

