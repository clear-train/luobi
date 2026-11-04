import AppKit

// MARK: - 把旧稿搬进来
//
// 真实情况是：稿子散在 Word、记事本、老电脑存的 txt 里。
// 所以这里不假设"你从零开始写"，而是尽量把已有文件读成纯文本：
//   .md/.txt  → 依次严格试 UTF-8 / GB18030 / Big5 / UTF-16，中文不会变乱码
//   .rtf      → AppKit 原生解析
//   .docx     → 系统自带 textutil 转纯文本（不引入任何第三方依赖）

enum TextImport {

    static let gb18030 = String.Encoding(
        rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)))
    static let big5 = String.Encoding(
        rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.big5.rawValue)))

    /// 文件 → 纯文本。不支持的格式返回 nil（调用方负责提示）。
    static func text(from url: URL) -> String? {
        switch url.pathExtension.lowercased() {
        case "rtf":  return rtfText(url)
        case "docx": return docxText(url)
        default:     return plainText(url)
        }
    }

    static func plainText(_ url: URL) -> String? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return decode(data)
    }

    /// 编码自动识别：谁能解出最多的中文字，就用谁。
    /// 直接"第一个不报错的编码"是不够的——GB18030 的字节能被 Latin1 全部解开，只是全是乱码。
    static func decode(_ data: Data) -> String? {
        if data.isEmpty { return "" }
        // UTF-8 能严格解开就是 UTF-8——这是强证据，不能让它跟别的编码"比中文字数"，
        // 因为 UTF-8 的字节流往往也能被 GB18030 解成一串汉字（全是乱的）。
        if let s = String(data: data, encoding: .utf8), !s.isEmpty, !s.contains("\u{FFFD}") {
            return s
        }
        // 带 BOM 的 UTF-16
        if data.count >= 2 {
            let b0 = data[0], b1 = data[1]
            if (b0 == 0xFF && b1 == 0xFE) || (b0 == 0xFE && b1 == 0xFF) {
                if let s = String(data: data, encoding: .utf16) { return s }
            }
        }
        var best: (String, Int)? = nil
        for enc in [gb18030, big5, .utf16LittleEndian, .isoLatin1] {
            guard let s = String(data: data, encoding: enc), !s.isEmpty, !s.contains("\u{FFFD}") else { continue }
            let score = cjkCount(s)
            if score > 0 {
                if best == nil || score > best!.1 { best = (s, score) }
            } else if best == nil {
                best = (s, 0)
            }
        }
        return best?.0 ?? String(data: data, encoding: .isoLatin1)
    }

    static func cjkCount(_ s: String) -> Int {
        var n = 0
        for u in s.unicodeScalars where (0x4E00...0x9FFF).contains(u.value) || (0x3400...0x4DBF).contains(u.value) {
            n += 1
        }
        return n
    }

    static func rtfText(_ url: URL) -> String? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let opts: [NSAttributedString.DocumentReadingOptionKey: Any] = [.documentType: NSAttributedString.DocumentType.rtf]
        if let a = try? NSAttributedString(data: data, options: opts, documentAttributes: nil) {
            return a.string
        }
        return decode(data)
    }

    static func docxText(_ url: URL) -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/textutil")
        p.arguments = ["-convert", "txt", "-stdout", url.path]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = Pipe()
        do { try p.run() } catch { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        guard p.terminationStatus == 0, !data.isEmpty else { return nil }
        return decode(data)
    }
}

extension EditorRoot {

    /// 真正的导入逻辑（不弹面板，方便测试）
    @discardableResult
    func importFiles(at urls: [URL]) -> (folder: String, imported: Int, failed: Int) {
        let stamp = DateFormatter()
        stamp.dateFormat = "yyyy-MM-dd"
        var name = "导入 " + stamp.string(from: Date())
        var n = 2
        while doc.folders.contains(where: { $0.name == name }) {
            name = "导入 " + stamp.string(from: Date()) + " (\(n))"
            n += 1
        }
        let folder = Folder(id: UUID().uuidString, name: name, expanded: true)
        doc.folders.append(folder)

        var imported = 0, failed = 0
        var usedTitles = Set<String>()
        for url in urls.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            guard let raw = TextImport.text(from: url) else { failed += 1; continue }
            let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { failed += 1; continue }
            var title = url.deletingPathExtension().lastPathComponent
            if title.isEmpty { title = "未命名" }
            if usedTitles.contains(title) {
                var k = 2
                while usedTitles.contains("\(title) (\(k))") { k += 1 }
                title = "\(title) (\(k))"
            }
            usedTitles.insert(title)
            doc.sheets.append(Sheet(id: UUID().uuidString, title: title, content: text, folderId: folder.id))
            imported += 1
        }

        if imported == 0 {
            doc.folders.removeAll { $0.id == folder.id }
            return (name, 0, failed)
        }
        refreshTable()
        if let last = doc.sheets.last(where: { $0.folderId == folder.id }) {
            switchTo(last.id)
        }
        return (name, imported, failed)
    }
}
