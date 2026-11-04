import AppKit
import UniformTypeIdentifiers

// MARK: - 文件输入输出：导出 / 导入 / 删除（菜单一格）
// 只依赖 Editor 公开接口，接线由 main.swift 完成

extension EditorRoot {

    // MARK: 导出目录与文件名

    private var exportDir: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("Luobi", isDirectory: true)
    }

    private var exportDirTilde: String {
        exportDir.path.replacingOccurrences(of: "/Users/\(NSUserName())", with: "~")
    }

    /// 非法文件名字符替换为下划线，空白标题用「未命名」
    private func safeBaseName(_ title: String) -> String {
        let illegal = CharacterSet(charactersIn: "/\\:*?\"<>|")
        var name = String(title.map { $0.unicodeScalars.contains { illegal.contains($0) } ? Character("_") : $0 })
        name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty { name = "未命名" }
        return name
    }

    /// 重名加 -2 -3 后缀，返回不存在的目标 URL
    private func uniqueURL(baseName: String, ext: String) -> URL {
        var url = exportDir.appendingPathComponent(baseName).appendingPathExtension(ext)
        var n = 1
        while FileManager.default.fileExists(atPath: url.path) {
            n += 1
            url = exportDir.appendingPathComponent("\(baseName)-\(n)").appendingPathExtension(ext)
        }
        return url
    }

    /// UTF-8 原子写，成功返回展示用的 ~ 缩写路径
    @discardableResult
    private func writeUTF8Atomic(_ text: String, to url: URL) throws -> String {
        let data = Data(text.utf8)
        try data.write(to: url, options: .atomic)
        return url.path.replacingOccurrences(of: "/Users/\(NSUserName())", with: "~")
    }

    private func markExported(_ short: String) {
        barLabel.stringValue = "已导出：\(short)"
    }

    // MARK: 1. 导出当前篇

    @objc func exportActiveSheet(_ sender: Any?) {
        guard let i = activeIndex else { barLabel.stringValue = "导出失败"; return }
        let sheet = doc.sheets[i]
        do {
            try FileManager.default.createDirectory(at: exportDir, withIntermediateDirectories: true)
            let url = uniqueURL(baseName: safeBaseName(sheet.title), ext: "md")
            let short = try writeUTF8Atomic(sheet.content, to: url)
            markExported(short)
        } catch {
            barLabel.stringValue = "导出失败"
        }
    }

    // MARK: 2. 导出全部文稿

    @objc func exportAllSheets(_ sender: Any?) {
        guard !doc.sheets.isEmpty else { barLabel.stringValue = "导出失败"; return }
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        let base = "全部文稿-\(fmt.string(from: Date()))"
        do {
            try FileManager.default.createDirectory(at: exportDir, withIntermediateDirectories: true)
            let body = doc.sheets.map { $0.content }.joined(separator: "\n\n---\n\n")
            let url = uniqueURL(baseName: base, ext: "md")
            let short = try writeUTF8Atomic(body, to: url)
            markExported(short)
        } catch {
            barLabel.stringValue = "导出失败"
        }
    }

    // MARK: 3. 导入 Markdown 文件

    @objc func importMDFiles(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        let mdType = UTType("net.daringfireball.markdown") ?? .plainText
        var types: [UTType] = [mdType, .plainText, .rtf]
        if let docx = UTType("org.openxmlformats.wordprocessingml.document") { types.append(docx) }
        panel.allowedContentTypes = types
        panel.message = "选择要导入的文件（Markdown / 文本 / Word / RTF，可多选）"
        guard panel.runModal() == .OK, !panel.urls.isEmpty else { return }

        let result = importFiles(at: panel.urls)
        if result.imported == 0 {
            barLabel.stringValue = "导入失败：\(result.failed) 个文件读不出文字"
        } else if result.failed > 0 {
            barLabel.stringValue = "已导入 \(result.imported) 篇到「\(result.folder)」，\(result.failed) 个失败"
        } else {
            barLabel.stringValue = "已导入 \(result.imported) 篇到「\(result.folder)」"
        }
    }

    // MARK: 4. 删除当前篇（至少保留一篇）

    @objc func deleteActiveSheet(_ sender: Any?) {
        guard let i = activeIndex else { return }
        let title = doc.sheets[i].title

        let alert = NSAlert()
        alert.messageText = "删除文稿"
        alert.informativeText = "确定删除「\(title)」吗？此操作不可撤销。"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "删除")
        alert.addButton(withTitle: "取消")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let count = doc.sheets.count
        var nextId: String
        if count > 1 {
            // 删除后切到相邻篇：优先下一篇，结尾则上一篇
            let next = i < count - 1 ? doc.sheets[i + 1] : doc.sheets[i - 1]
            nextId = next.id
            doc.sheets.remove(at: i)
        } else {
            // 最后一篇：删掉后立即补一篇空稿，永不归零
            let s = Sheet(id: UUID().uuidString, title: "未命名", content: "")
            doc.sheets = [s]
            nextId = s.id
        }
        switchTo(nextId)   // 自带 refreshTable + persistNow
    }

    /// 在 Finder 里打开文稿库目录（帮助菜单）
    @objc func openVaultFolder(_ sender: Any?) {
        Vault.ensure()
        NSWorkspace.shared.open(Vault.dir)
    }
}
