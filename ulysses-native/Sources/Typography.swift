import AppKit

// MARK: - 排版美学（对应 HTML 版：衬线正文 + 宽松行距）
// HTML 版之所以好看：正文 Songti SC / Georgia 衬线，行高 1.95，字距 0.01em。
// AppKit 默认是无衬线系统字体 + 紧密行距，所以"字不如 HTML 好看"。这里统一接管。

enum Typo {
    /// 基准正文字号；界面里的「正文字号」滑块通过 scale 缩放整套排版
    static let baseBodySize: CGFloat = 17
    static var scale: CGFloat = 1
    static var bodySize: CGFloat { baseBodySize * scale }

    /// 正文字体：优先宋体（中文衬线），拉丁字符落到 Georgia 观感
    static func serif(_ size: CGFloat, bold: Bool = false) -> NSFont {
        let names = bold
            ? ["SongtiSC-Bold", "STSongti-SC-Bold", "Songti SC Bold"]
            : ["SongtiSC-Regular", "STSongti-SC-Regular", "Songti SC"]
        for n in names {
            if let f = NSFont(name: n, size: size) { return f }
        }
        // 兜底：系统字体转粗
        let base = NSFont.systemFont(ofSize: size)
        return bold ? NSFontManager.shared.convert(base, toHaveTrait: .boldFontMask) : base
    }

    static var body: NSFont { serif(bodySize) }
    static func bold(_ size: CGFloat) -> NSFont { serif(size, bold: true) }

    /// 标题字号档位（# ~ ######）
    static func heading(_ level: Int) -> NSFont {
        let sizes: [CGFloat] = [26, 23, 20, 18, 17, 16]
        let i = max(1, min(6, level)) - 1
        return serif(sizes[i] * scale, bold: true)
    }

    /// 正文段落：行距等于 HTML 的 1.95 行高观感
    static var bodyParagraph: NSParagraphStyle {
        let p = NSMutableParagraphStyle()
        p.lineSpacing = 10 * scale
        p.paragraphSpacing = 10 * scale
        p.lineBreakMode = .byWordWrapping
        return p
    }

    static var bodyAttributes: [NSAttributedString.Key: Any] {
        [
            .font: body,
            .foregroundColor: NSColor.labelColor,
            .kern: 0.3,
            .paragraphStyle: bodyParagraph,
        ]
    }

    /// 标题段落（自己带间距，避免和正文挤在一起）
    static func headingParagraph() -> NSParagraphStyle {
        let p = NSMutableParagraphStyle()
        p.lineSpacing = 4
        p.paragraphSpacingBefore = 10
        p.paragraphSpacing = 8
        return p
    }
}
