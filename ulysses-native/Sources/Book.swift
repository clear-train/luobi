import AppKit

// MARK: - 导出整本书
//
// 单篇导出是「拿走一章」，这里解决的是「把写完的稿子变成一份能发给别人的东西」。
// 顺序完全跟随侧栏：同一层先放文稿，再放分组；分组的名字会变成一个标题，
// 里面的文稿按侧栏顺序排在它下面。所以你在侧栏看到的顺序，就是成书顺序。

struct BookChapter {
    let title: String
    let content: String
    let level: Int      // 1 = 书名，2 = 一级分组，3 = 文稿…
    let isGroup: Bool
}

extension DocState {

    /// 按侧栏顺序展开成章节列表。scope = 某个分组时，只导出它和它的子分组。
    /// 能进书的文稿：人物卡片不是章节，别混进正文
    func chapters(in folderId: String?) -> [Sheet] {
        sheets(in: folderId).filter { $0.card == nil }
    }

    func bookChapters(scope: String?, numbering: Bool = true) -> [BookChapter] {
        var out: [BookChapter] = []

        // 章号按「分组内第几篇」算，换分组就重新从第一章开始
        func emit(_ sheet: Sheet, level: Int, index: Int, inFolder: Bool) {
            let title = (numbering && inFolder) ? numberedTitle(sheet.title, index: index) : sheet.title
            out.append(BookChapter(title: title, content: sheet.content,
                                   level: min(level, 6), isGroup: false))
        }
        // 只装卡片的空分组不该在成书里留下一个空标题
        func hasChapters(_ folderId: String) -> Bool {
            if !chapters(in: folderId).isEmpty { return true }
            return childFolders(of: folderId).contains { hasChapters($0.id) }
        }
        func walkChildren(of parent: String?, depth: Int) {
            for f in childFolders(of: parent) {
                guard hasChapters(f.id) else { continue }
                out.append(BookChapter(title: f.name, content: "", level: min(depth, 5), isGroup: true))
                var i = 0
                for s in chapters(in: f.id) { i += 1; emit(s, level: depth + 1, index: i, inFolder: true) }
                walkChildren(of: f.id, depth: depth + 1)
            }
        }

        let startParent: String? = scope.flatMap { folder(id: $0) != nil ? $0 : nil }
        if startParent != nil {
            // 只导某个分组时：组里的文稿就是这部书的章节，先排它们、再排子分组
            var i = 0
            for s in chapters(in: startParent) { i += 1; emit(s, level: 2, index: i, inFolder: true) }
            walkChildren(of: startParent, depth: 2)
        } else {
            // 整库导出：先走分组（那才是"书"），没归组的零散文稿放最后，不至于把后记插到正文中间
            walkChildren(of: startParent, depth: 2)
            for s in chapters(in: startParent) { emit(s, level: 2, index: 0, inFolder: false) }
        }
        return out
    }

    /// 「开始的地方」→「第一章 · 开始的地方」；已经自带「第 x 章」的就不再套一层
    func numberedTitle(_ title: String, index: Int) -> String {
        let t = title.trimmingCharacters(in: .whitespaces)
        if t.hasPrefix("第"), t.contains("章") || t.contains("节") { return t }
        let num = chineseNumber(index)
        if t.isEmpty { return "第\(num)章" }
        return "第\(num)章 · \(t)"
    }

    /// 1 → 一，12 → 十二，23 → 二十三（只到 99，够小说用）
    func chineseNumber(_ n: Int) -> String {
        if n <= 0 { return "\(n)" }
        if n > 99 { return "\(n)" }
        let digits = ["零", "一", "二", "三", "四", "五", "六", "七", "八", "九"]
        if n < 10 { return digits[n] }
        let tens = n / 10, ones = n % 10
        var s = tens == 1 ? "十" : digits[tens] + "十"
        if ones > 0 { s += digits[ones] }
        return s
    }

    /// 导出 Word 能直接打开的 RTF。
    /// 选 RTF 不选 .docx 的原因：docx 是 zip + OOXML，要自己写压缩和一堆 XML；
    /// 而 RTF 是纯文本格式，AppKit 原生支持写出，Word/WPS/Pages 都能打开。
    func bookRTF(title: String, scope: String? = nil, numbering: Bool = true) -> Data? {
        let chapters = bookChapters(scope: scope, numbering: numbering)
        let bodyFont = NSFont(name: "STSongti-SC-Regular", size: 12) ?? NSFont.systemFont(ofSize: 12)
        let out = NSMutableAttributedString()

        func para(_ align: NSTextAlignment, spacing: CGFloat, indent: CGFloat = 0, line: CGFloat = 6) -> NSParagraphStyle {
            let p = NSMutableParagraphStyle()
            p.alignment = align
            p.paragraphSpacing = spacing
            p.lineSpacing = line
            p.firstLineHeadIndent = indent
            return p
        }

        let titleFont = NSFont(name: "STSongti-SC-Bold", size: 22) ?? NSFont.boldSystemFont(ofSize: 22)
        out.append(NSAttributedString(string: title + "\n", attributes: [
            .font: titleFont,
            .foregroundColor: NSColor.black,
            .paragraphStyle: para(.center, spacing: 18, line: 8),
        ]))

        let words = chapters.reduce(0) {
            $0 + ($1.isGroup ? 0 : statCJK($1.content) + statLatin($1.content))
        }
        out.append(NSAttributedString(string: "共 \(chapters.filter { !$0.isGroup }.count) 章 · 约 \(words) 字\n\n", attributes: [
            .font: bodyFont,
            .foregroundColor: NSColor.darkGray,
            .paragraphStyle: para(.center, spacing: 14),
        ]))

        for ch in chapters {
            if ch.isGroup {
                let size: CGFloat = ch.level <= 1 ? 16 : 14
                let hFont = NSFont(name: "STSongti-SC-Bold", size: size) ?? NSFont.boldSystemFont(ofSize: size)
                out.append(NSAttributedString(string: ch.title + "\n", attributes: [
                    .font: hFont,
                    .foregroundColor: NSColor.black,
                    .paragraphStyle: para(.left, spacing: 10, line: 8),
                ]))
                continue
            }

            out.append(NSAttributedString(string: ch.title + "\n", attributes: [
                .font: (NSFont(name: "STSongti-SC-Bold", size: 14) ?? NSFont.boldSystemFont(ofSize: 14)),
                .foregroundColor: NSColor.black,
                .paragraphStyle: para(.left, spacing: 8, line: 8),
            ]))

            for raw in ch.content.components(separatedBy: "\n") {
                let line = raw.trimmingCharacters(in: .whitespaces)
                if line.isEmpty {
                    out.append(NSAttributedString(string: "\n", attributes: [.font: bodyFont]))
                    continue
                }
                if line.hasPrefix("#") {
                    let text = String(line.drop { $0 == "#" }).trimmingCharacters(in: .whitespaces)
                    out.append(NSAttributedString(string: text + "\n", attributes: [
                        .font: (NSFont(name: "STSongti-SC-Bold", size: 13) ?? NSFont.boldSystemFont(ofSize: 13)),
                        .foregroundColor: NSColor.black,
                        .paragraphStyle: para(.left, spacing: 8, line: 8),
                    ]))
                    continue
                }
                if line.hasPrefix(">") {
                    let text = String(line.dropFirst()).trimmingCharacters(in: .whitespaces)
                    out.append(NSAttributedString(string: text + "\n", attributes: [
                        .font: NSFont(name: "STSongti-SC-Regular", size: 11.5) ?? NSFont.systemFont(ofSize: 11.5),
                        .foregroundColor: NSColor.darkGray,
                        .paragraphStyle: para(.left, spacing: 6, indent: 18, line: 5),
                    ]))
                    continue
                }
                out.append(NSAttributedString(string: line + "\n", attributes: [
                    .font: bodyFont,
                    .foregroundColor: NSColor.black,
                    .paragraphStyle: para(.justified, spacing: 6, indent: 24, line: 6),
                ]))
            }
            out.append(NSAttributedString(string: "\n", attributes: [.font: bodyFont]))
        }

        let attrs: [NSAttributedString.DocumentAttributeKey: Any] = [
            .documentType: NSAttributedString.DocumentType.rtf,
            .title: title,
        ]
        return try? out.data(from: NSRange(location: 0, length: out.length), documentAttributes: attrs)
    }

    func bookMarkdown(title: String, scope: String? = nil, numbering: Bool = true) -> String {
        let chapters = bookChapters(scope: scope, numbering: numbering)
        var lines: [String] = []
        lines.append("# " + title)
        let words = chapters.reduce(0) { $0 + ($1.isGroup ? 0 : statCJK($1.content) + statLatin($1.content)) }
        lines.append("> 共 \(chapters.filter { !$0.isGroup }.count) 篇，约 \(words) 字。用 Ulysses Native 导出。")
        for c in chapters {
            if c.isGroup {
                lines.append(String(repeating: "#", count: c.level) + " " + c.title)
                continue
            }
            lines.append(String(repeating: "#", count: c.level) + " " + c.title)
            let body = c.content.trimmingCharacters(in: .whitespacesAndNewlines)
            if !body.isEmpty { lines.append(body) }
        }
        return lines.joined(separator: "\n\n") + "\n"
    }

    /// 网页版本：不想装 Markdown 编辑器的人，双击就能在浏览器里看/打印
    func bookHTML(title: String, scope: String? = nil, numbering: Bool = true) -> String {
        let chapters = bookChapters(scope: scope, numbering: numbering)
        let words = chapters.reduce(0) { $0 + ($1.isGroup ? 0 : statCJK($1.content) + statLatin($1.content)) }
        var body: [String] = []
        for c in chapters {
            let tag = "h\(min(c.level, 6))"
            body.append("<\(tag)>\(escapeHTML(c.title))</\(tag)>")
            if !c.isGroup {
                body.append(miniMarkdownToHTML(c.content))
            }
        }
        return """
        <!doctype html>
        <html lang="zh-CN">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>\(escapeHTML(title))</title>
        <style>
          :root { color-scheme: light; }
          body {
            max-width: 40em; margin: 0 auto; padding: 64px 24px 96px;
            background: #F6F2E7; color: #2B2620;
            font-family: "Songti SC", "STSongti-SC-Regular", "Noto Serif CJK SC", serif;
            font-size: 17px; line-height: 1.95; letter-spacing: 0.02em;
          }
          h1 { font-size: 2.1em; text-align: center; margin: 0 0 2.4em; letter-spacing: 0.06em; }
          h2 { font-size: 1.5em; margin: 2.6em 0 1em; }
          h3 { font-size: 1.25em; margin: 2em 0 0.8em; }
          h4, h5, h6 { font-size: 1.1em; margin: 1.6em 0 0.6em; }
          p { text-indent: 2em; margin: 0 0 0.9em; }
          blockquote {
            text-indent: 0; margin: 1.4em 0; padding-left: 1em;
            border-left: 3px solid rgba(43,38,32,0.18); color: rgba(43,38,32,0.62);
            font-style: italic;
          }
          .meta { text-align: center; color: rgba(43,38,32,0.55); text-indent: 0; margin-bottom: 3em; font-size: 0.9em; }
          @media print {
            body { background: #fff; color: #000; padding: 0; max-width: none; }
            h1, h2, h3 { page-break-after: avoid; }
            p, blockquote { page-break-inside: avoid; }
          }
        </style>
        </head>
        <body>
        <h1>\(escapeHTML(title))</h1>
        <p class="meta">共 \(chapters.filter { !$0.isGroup }.count) 篇，约 \(words) 字</p>
        \(body.joined(separator: "\n"))
        </body>
        </html>
        """
    }
}

// MARK: - 极简 Markdown → HTML（只认标题、引用、加粗、空行分段）

func escapeHTML(_ s: String) -> String {
    s.replacingOccurrences(of: "&", with: "&amp;")
        .replacingOccurrences(of: "<", with: "&lt;")
        .replacingOccurrences(of: ">", with: "&gt;")
}

func miniMarkdownToHTML(_ text: String) -> String {
    var out: [String] = []
    var paragraph: [String] = []

    func flushParagraph() {
        guard !paragraph.isEmpty else { return }
        let joined = paragraph.joined()
        out.append("<p>" + inlineHTML(joined) + "</p>")
        paragraph.removeAll()
    }

    for raw in text.components(separatedBy: "\n") {
        let line = raw.trimmingCharacters(in: .whitespaces)
        if line.isEmpty { flushParagraph(); continue }
        let hashes = line.prefix { $0 == "#" }.count
        if hashes >= 1 && hashes <= 6, line.dropFirst(hashes).hasPrefix(" ") {
            flushParagraph()
            let title = line.dropFirst(hashes).trimmingCharacters(in: .whitespaces)
            out.append("<h\(hashes + 2)>" + inlineHTML(title) + "</h\(hashes + 2)>")
            continue
        }
        if line.hasPrefix("> ") {
            flushParagraph()
            out.append("<blockquote>" + inlineHTML(String(line.dropFirst(2))) + "</blockquote>")
            continue
        }
        if line == "---" { flushParagraph(); out.append("<hr>"); continue }
        paragraph.append(line)
    }
    flushParagraph()
    return out.joined(separator: "\n")
}

func inlineHTML(_ s: String) -> String {
    var result = escapeHTML(s)
    // **加粗**
    while let a = result.range(of: "**") {
        guard let b = result.range(of: "**", range: a.upperBound..<result.endIndex) else { break }
        let inner = String(result[a.upperBound..<b.lowerBound])
        result.replaceSubrange(a.lowerBound..<b.upperBound, with: "<strong>" + inner + "</strong>")
    }
    return result
}

// MARK: - 界面入口

extension EditorRoot {

    @objc func exportBook(_ sender: Any?) {
        let alert = NSAlert()
        alert.messageText = "导出整本书"
        alert.informativeText = "顺序跟侧栏一致：同一层先放文稿、再放分组，分组的名字会变成标题。"
        alert.addButton(withTitle: "导出")
        alert.addButton(withTitle: "取消")

        let defaultTitle: String = {
            if let i = doc.sheets.firstIndex(where: { $0.id == doc.activeId }),
               let fid = doc.sheets[i].folderId, let f = doc.folder(id: fid) {
                return f.name
            }
            return "我的书"
        }()

        let titleField = NSTextField(string: defaultTitle)
        titleField.frame = NSRect(x: 0, y: 0, width: 260, height: 24)

        let formatPopup = NSPopUpButton(frame: .zero, pullsDown: false)
        formatPopup.addItems(withTitles: ["网页（.html，双击就能看/打印）", "Markdown（.md，还能继续改）", "Word（.rtf，发给编辑直接能开）"])

        let scopePopup = NSPopUpButton(frame: .zero, pullsDown: false)
        scopePopup.addItems(withTitles: ["全部文稿", "当前分组及其子分组"])
        if doc.sheets.first(where: { $0.id == doc.activeId })?.folderId == nil {
            scopePopup.item(at: 1)?.isEnabled = false
        }

        let numberingBox = NSButton(checkboxWithTitle: "自动加章号（第一章 · 开始的地方）", target: nil, action: nil)
        numberingBox.state = .on

        let grid = NSGridView(views: [
            [NSTextField(labelWithString: "书名"), titleField],
            [NSTextField(labelWithString: "格式"), formatPopup],
            [NSTextField(labelWithString: "范围"), scopePopup],
            [NSGridCell.emptyContentView, numberingBox],
        ])
        grid.rowSpacing = 8
        grid.columnSpacing = 10
        grid.column(at: 0).xPlacement = .trailing
        grid.frame = NSRect(x: 0, y: 0, width: 380, height: 124)
        alert.accessoryView = grid

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let title = titleField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let bookTitle = title.isEmpty ? "我的书" : title
        let format = formatPopup.indexOfSelectedItem
        let scope: String? = scopePopup.indexOfSelectedItem == 1
            ? doc.sheets.first(where: { $0.id == doc.activeId })?.folderId
            : nil
        let ext = ["html", "md", "rtf"][max(0, min(2, format))]
        let numbering = (numberingBox.state == .on)
        let words = doc.bookChapters(scope: scope).reduce(0) {
            $0 + ($1.isGroup ? 0 : statCJK($1.content) + statLatin($1.content))
        }

        do {
            try FileManager.default.createDirectory(at: bookExportDir, withIntermediateDirectories: true)
            let url = bookUniqueURL(baseName: bookSafeName(bookTitle), ext: ext)
            if ext == "rtf" {
                guard let rtf = doc.bookRTF(title: bookTitle, scope: scope, numbering: numbering) else {
                    barLabel.stringValue = "导出 Word 失败：系统没写出 RTF（可以选网页或 Markdown）"
                    return
                }
                try rtf.write(to: url, options: .atomic)
            } else {
                let content = (ext == "html")
                    ? doc.bookHTML(title: bookTitle, scope: scope, numbering: numbering)
                    : doc.bookMarkdown(title: bookTitle, scope: scope, numbering: numbering)
                try Data(content.utf8).write(to: url, options: .atomic)
            }
            let short = url.path.replacingOccurrences(of: "/Users/\(NSUserName())", with: "~")
            barLabel.stringValue = "已成书：\(short) · 约 \(words) 字"
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch {
            barLabel.stringValue = "成书失败：写不进导出目录"
        }
    }

    /// 成书文件与单篇导出放同一个目录，找的时候只需要记一个地方
    private var bookExportDir: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("UlyssesNative", isDirectory: true)
    }

    private func bookSafeName(_ title: String) -> String {
        let illegal = CharacterSet(charactersIn: "/\\:*?\"<>|")
        var name = String(title.map { $0.unicodeScalars.contains { illegal.contains($0) } ? Character("_") : $0 })
        name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "我的书" : name
    }

    private func bookUniqueURL(baseName: String, ext: String) -> URL {
        var url = bookExportDir.appendingPathComponent(baseName).appendingPathExtension(ext)
        var n = 1
        while FileManager.default.fileExists(atPath: url.path) {
            n += 1
            url = bookExportDir.appendingPathComponent("\(baseName)-\(n)").appendingPathExtension(ext)
        }
        return url
    }
}
