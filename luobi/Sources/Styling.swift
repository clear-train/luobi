import AppKit

// 标题字号档位交给 Typography 统一管理（衬线 + 粗细一致）
// 字号可调，所以每次排版按当前 scale 现算（六个字体实例，成本可忽略）
private var headingFonts: [NSFont] { (1...6).map { Typo.heading($0) } }

// MARK: - 排版引擎：Markdown → 文本属性

extension EditorRoot {
    // 100ms 防抖的排版（跟手，但不逐键）
    // around: 只重排这个范围覆盖的段落（打字时）；nil = 全文（开文档 / 换主题 / 改字号）
    func restyleSoon(around range: NSRange? = nil) {
        pendingStyleRange = range
        styleTimer?.invalidate()
        styleTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            let pending = self.pendingStyleRange
            self.pendingStyleRange = nil
            self.applyMarkdownStyling(in: pending)
        }
    }

    func applyMarkdownStyling(in range: NSRange? = nil) {
        let storage = textView.textStorage!
        let ns = storage.string as NSString
        let target: NSRange
        if let r = range, ns.length > 0 {
            let clamped = NSRange(location: max(0, min(r.location, ns.length)),
                                  length: 0)
            target = ns.paragraphRange(for: clamped)
        } else {
            target = NSRange(location: 0, length: ns.length)
        }
        guard target.length > 0 else { return }

        // 长文里重排属性会让 NSTextView 自己重算可见区域，把视口甩走一屏
        // ——用户看到的就是"写着写着突然跳回最上面"。所以重排前后自己守住视口和光标。
        let clip = textView.enclosingScrollView?.contentView
        let savedOrigin = clip?.bounds.origin
        let savedSelection = textView.selectedRange()
        let savedTyping = textView.typingAttributes

        storage.setAttributes(bodyAttributes, range: target)
        if doc.markdown {
            styleParagraphs(storage, in: target)
        }
        if readingMode { hideMarkers(storage, in: target) }
        textView.typingAttributes = savedTyping

        if textView.selectedRange() != savedSelection,
           NSMaxRange(savedSelection) <= storage.length {
            textView.setSelectedRange(savedSelection)
        }
        if let clip = clip, let origin = savedOrigin {
            let maxY = max(0, textView.frame.height - clip.bounds.height)
            clip.scroll(to: NSPoint(x: 0, y: min(max(0, origin.y), maxY)))
            textView.enclosingScrollView?.reflectScrolledClipView(clip)
        }
        ensureCaretVisible()
    }

    /// 只给 target 范围内的每一行上样式（标题 / 加粗 / 引用）
    private func styleParagraphs(_ storage: NSTextStorage, in target: NSRange) {
        let ns = storage.string as NSString
        ns.enumerateSubstrings(in: target, options: [.byLines]) { [weak self] line, _, enclosing, _ in
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
    }

    /// 重排后如果光标被挤到可视区外，只做最小滚动把它带回来（不整页跳）
    private func ensureCaretVisible() {
        guard let lm = textView.layoutManager, let tc = textView.textContainer else { return }
        let sel = textView.selectedRange()
        let len = (textView.string as NSString).length
        guard sel.location <= len else { return }
        let gr = lm.glyphRange(forCharacterRange: sel, actualCharacterRange: nil)
        var caret = lm.boundingRect(forGlyphRange: gr, in: tc)
        caret.origin.x += textView.textContainerInset.width
        caret.origin.y += textView.textContainerInset.height
        if !textView.visibleRect.insetBy(dx: 0, dy: -2).contains(caret) {
            textView.scrollToVisible(caret)
        }
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
