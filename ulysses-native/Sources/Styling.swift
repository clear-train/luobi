import AppKit

// 标题字号档位（extension 不能存属性，用文件级缓存代替）
private let _cachedHeadingFonts: [NSFont] = [
    NSFont.boldSystemFont(ofSize: 26),
    NSFont.boldSystemFont(ofSize: 23),
    NSFont.boldSystemFont(ofSize: 20),
    NSFont.boldSystemFont(ofSize: 18),
    NSFont.boldSystemFont(ofSize: 17),
    NSFont.boldSystemFont(ofSize: 16),
]

// MARK: - 排版引擎：Markdown → 文本属性

extension EditorRoot {
    // 100ms 防抖的排版（跟手，但不逐键）
    func restyleSoon() {
        styleTimer?.invalidate()
        styleTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: false) { [weak self] _ in
            self?.applyMarkdownStyling()
        }
    }

    func applyMarkdownStyling() {
        let storage = textView.textStorage!
        let full = NSRange(location: 0, length: storage.length)
        guard doc.markdown else {
            storage.setAttributes([.font: baseFont], range: full)
            return
        }
        storage.setAttributes([
            .font: baseFont,
            .foregroundColor: NSColor.labelColor,
        ], range: full)

        let ns = storage.string as NSString
        if full.length == 0 { return }
        ns.enumerateSubstrings(in: full, options: [.byLines]) { [weak self] line, _, enclosing, _ in
            guard let self = self, let line = line else { return }
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { return }

            // # 标题
            let hashCount = trimmed.prefix { $0 == "#" }.count
            if hashCount >= 1 && hashCount <= 6 {
                let rest = trimmed.dropFirst(hashCount)
                if rest.isEmpty || rest.hasPrefix(" ") || rest.hasPrefix("\t") {
                    let para = NSMutableParagraphStyle()
                    para.paragraphSpacing = 8
                    storage.addAttributes([
                        .font: _cachedHeadingFonts[hashCount - 1],
                        .paragraphStyle: para,
                    ], range: enclosing)
                    return
                }
            }

            // **加粗**
            var searchStart = line.startIndex
            while let first = line.range(of: "**", range: searchStart..<line.endIndex) {
                if let close = line.range(of: "**", range: first.upperBound..<line.endIndex) {
                    let inner = first.upperBound..<close.lowerBound
                    let r = NSRange(inner, in: line)
                    let shifted = NSRange(location: enclosing.location + r.location, length: r.length)
                    if shifted.length > 0 {
                        storage.addAttributes([.font: NSFont.boldSystemFont(ofSize: 17)], range: shifted)
                    }
                    searchStart = close.upperBound
                } else {
                    break
                }
            }

            // > 引用
            if trimmed.hasPrefix(">") {
                storage.addAttributes([
                    .font: NSFontManager.shared.convert(self.baseFont, toHaveTrait: [.italicFontMask]),
                    .foregroundColor: NSColor.secondaryLabelColor,
                ], range: enclosing)
            }
        }
    }
}
