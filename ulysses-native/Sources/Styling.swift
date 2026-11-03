import AppKit

// 标题字号档位交给 Typography 统一管理（衬线 + 粗细一致）
// 字号可调，所以每次排版按当前 scale 现算（六个字体实例，成本可忽略）
private var headingFonts: [NSFont] { (1...6).map { Typo.heading($0) } }

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
            storage.setAttributes(bodyAttributes, range: full)
            return
        }
        storage.setAttributes(bodyAttributes, range: full)

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
                    storage.addAttributes([
                        .font: headingFonts[hashCount - 1],
                        .paragraphStyle: Typo.headingParagraph(),
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
                        storage.addAttributes([.font: Typo.bold(17)], range: shifted)
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

        // 阅读模式下把标记符号藏起来（保留字符，只是看不见——不破坏正文和光标位置）
        if readingMode { hideMarkers(storage, in: full) }
    }

    /// 把 # ** > - 这些标记本身变成透明。阅读时只该看到文字，不该看到语法。
    private func hideMarkers(_ storage: NSTextStorage, in full: NSRange) {
        let ns = storage.string as NSString
        var ranges: [NSRange] = []
        ns.enumerateSubstrings(in: full, options: [.byLines]) { line, _, enclosing, _ in
            guard let line = line else { return }
            let lead = line.prefix { $0 == " " || $0 == "\t" }.count
            let t = line.trimmingCharacters(in: .whitespaces)
            var len = 0
            if t.hasPrefix("#") {
                let h = t.prefix { $0 == "#" }.count
                let after = t.dropFirst(h)
                if h <= 6, after.isEmpty || after.hasPrefix(" ") {
                    len = h + (after.hasPrefix(" ") ? 1 : 0)
                }
            } else if t.hasPrefix("> ") || t.hasPrefix("- ") || t.hasPrefix("* ") {
                len = 2
            }
            if len > 0 {
                ranges.append(NSRange(location: enclosing.location + lead, length: len))
            }
            var from = line.startIndex
            while let a = line.range(of: "**", range: from..<line.endIndex) {
                ranges.append(NSRange(location: enclosing.location + NSRange(a, in: line).location, length: 2))
                from = a.upperBound
            }
        }
        for r in ranges where r.length > 0 && NSMaxRange(r) <= storage.length {
            storage.addAttribute(.foregroundColor, value: NSColor.clear, range: r)
        }
    }
}
