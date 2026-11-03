import AppKit

// MARK: - 备份与恢复（快照存在 state.json 旁边的 Backups/ 里）
//
// 设计取舍：写作工具最怕「稿子没了」，比任何花哨功能都重要。
// 所以这里做三件事：
//   1. 每次保存前，把旧的 state.json 复制成 state.json.bak（一步后悔药）
//   2. 每 5 分钟存一份带时间戳的快照，最多留 20 份（慢慢后悔药）
//   3. 主文件读不出来时，自动从 .bak → 最新快照逐级兜底（被动保险）

extension EditorRoot {

    /// 文件菜单「立即备份」：不用等 5 分钟，马上存一份快照
    @objc func backupNow(_ sender: Any?) {
        if let url = Vault.snapshotNow(doc) {
            startupNote = "已备份：" + url.lastPathComponent
        } else {
            startupNote = "备份失败：写不进 Backups 目录"
        }
        refreshBar()
    }

    /// 文件菜单「从备份恢复…」：列出所有快照，选一个就换回来
    @objc func showBackupPanel(_ sender: Any?) {
        let entries = Vault.listBackups()
        let alert = NSAlert()
        alert.messageText = "从备份恢复"
        guard !entries.isEmpty else {
            alert.informativeText = "还没有任何快照。点「立即备份」先存一份，或者等自动保存满 5 分钟。"
            alert.addButton(withTitle: "好")
            alert.runModal()
            return
        }
        alert.informativeText = "快照每 5 分钟存一份，最多保留 20 份。恢复会覆盖当前的文稿库（当前内容会先自动存成一份新快照，所以不会丢）。"
        alert.addButton(withTitle: "恢复这个")
        alert.addButton(withTitle: "取消")

        let popup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 380, height: 26), pullsDown: false)
        popup.addItems(withTitles: entries.map { $0.title })
        alert.accessoryView = popup

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let idx = popup.indexOfSelectedItem
        guard idx >= 0, idx < entries.count else { return }
        let picked = entries[idx]
        guard let restored = Vault.restore(from: picked.url) else {
            startupNote = "这份备份读不出来，换一份试试"
            refreshBar()
            return
        }
        // 覆盖前先把当前内容存一份，避免"恢复错了"变成"什么都没了"
        Vault.snapshotNow(doc)
        adoptDoc(restored)
        persistNow()
        startupNote = "已从 \(picked.title) 恢复"
        refreshBar()
    }

    /// 文件菜单「打开备份文件夹」
    @objc func openBackupFolder(_ sender: Any?) {
        Vault.ensure()
        NSWorkspace.shared.open(Vault.backupsDir)
    }
}
