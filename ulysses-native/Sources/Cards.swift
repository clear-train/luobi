import AppKit

// MARK: - 人物 / 设定卡片
//
// 写长篇时最难记的不是情节，是"这个人第三章说过什么、和谁什么关系"。
// 卡片把姓名、关系、外貌、口头禅从正文里拎出来变成结构化的几栏；
// 正文里按住 ⌘ 点名字就能弹出这张卡，不用在侧栏里翻。

/// 从上往下排的容器（卡片弹窗里逐行量高度，翻转坐标更省心）
final class FlippedStackView: NSView {
    override var isFlipped: Bool { true }
}

/// 带"⌘ 点名字"能力的正文视图
final class CardTextView: NSTextView {
    var cardClickHandler: ((NSPoint) -> Bool)?

    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.command) {
            let p = convert(event.locationInWindow, from: nil)
            if cardClickHandler?(p) == true { return }
        }
        super.mouseDown(with: event)
    }
}

extension EditorRoot {

    // MARK: 新建 / 编辑

    @objc func newCardSheet(_ sender: Any?) {
        var card = CardData()
        card.name = "新人物"
        var folder: String? = nil
        if table.selectedRow >= 0, let it = table.item(atRow: table.selectedRow) as? SideItem, let f = it.folder {
            folder = f.id
        }
        let sheet = Sheet(id: UUID().uuidString, title: "新人物", content: "",
                          updatedAt: Date().timeIntervalSince1970, folderId: folder, card: card)
        doc.sheets.append(sheet)
        doc.activeId = sheet.id
        refreshTable()
        persistNow()
        editCard(id: sheet.id)
    }

    /// 侧栏里「编辑卡片信息…」/ 双击卡片
    @objc func openSelectedCard(_ sender: Any?) {
        guard let it = contextSideItem(), let s = it.sheet, s.card != nil else { return }
        editCard(id: s.id)
    }

    @objc func editCardMenu(_ sender: Any?) { openSelectedCard(sender) }

    /// 卡片编辑面板：五栏，保存后同步文稿标题与备注
    func editCard(id: String) {
        guard let idx = doc.sheets.firstIndex(where: { $0.id == id }),
              let card = doc.sheets[idx].card else { return }

        let alert = NSAlert()
        alert.messageText = "人物卡片"
        alert.informativeText = "这些字段只在卡片里，不会混进正文；正文里按住 ⌘ 点名字可以随时看。"
        alert.addButton(withTitle: "保存")
        alert.addButton(withTitle: "取消")

        let nameField = NSTextField(string: card.name)
        let relationField = NSTextField(string: card.relation)
        let lookField = NSTextField(string: card.appearance)
        let phraseField = NSTextField(string: card.catchphrase)
        let noteField = NSTextField(string: doc.sheets[idx].content)
        for f in [nameField, relationField, lookField, phraseField, noteField] {
            f.translatesAutoresizingMaskIntoConstraints = false
            f.widthAnchor.constraint(equalToConstant: 260).isActive = true
        }
        noteField.placeholderString = "备注：出场章节、口头禅的由来……"

        let grid = NSGridView(views: [
            [NSTextField(labelWithString: "姓名"), nameField],
            [NSTextField(labelWithString: "关系"), relationField],
            [NSTextField(labelWithString: "外貌"), lookField],
            [NSTextField(labelWithString: "口头禅"), phraseField],
            [NSTextField(labelWithString: "备注"), noteField],
        ])
        grid.rowSpacing = 8
        grid.columnSpacing = 10
        grid.column(at: 0).xPlacement = .trailing
        grid.frame = NSRect(x: 0, y: 0, width: 360, height: 150)
        alert.accessoryView = grid

        let apply: (NSApplication.ModalResponse) -> Void = { [weak self] resp in
            guard let self = self, resp == .alertFirstButtonReturn else { return }
            guard let i = self.doc.sheets.firstIndex(where: { $0.id == id }) else { return }
            var c = self.doc.sheets[i].card ?? CardData()
            c.name = nameField.stringValue.trimmingCharacters(in: .whitespaces)
            c.relation = relationField.stringValue
            c.appearance = lookField.stringValue
            c.catchphrase = phraseField.stringValue
            self.doc.sheets[i].card = c
            self.doc.sheets[i].content = noteField.stringValue
            self.doc.sheets[i].title = c.name.isEmpty ? "未命名人物" : c.name
            self.doc.sheets[i].updatedAt = Date().timeIntervalSince1970
            self.refreshTable()
            self.persistNow()
            if self.doc.activeId == id { self.switchTo(id) }
        }

        if let win = window {
            alert.beginSheetModal(for: win, completionHandler: apply)
        } else {
            apply(alert.runModal())
        }
    }

    // MARK: ⌘ 点名字弹卡片

    func cardAt(point: NSPoint) -> (Sheet, NSRect)? {
        guard !doc.cardSheets.isEmpty else { return nil }
        guard let lm = textView.layoutManager, let tc = textView.textContainer else { return nil }
        var p = point
        p.x -= textView.textContainerInset.width
        p.y -= textView.textContainerInset.height
        var frac: CGFloat = 0
        let idx = lm.characterIndex(for: p, in: tc, fractionOfDistanceBetweenInsertionPoints: &frac)
        let str = textView.string as NSString
        guard idx >= 0, idx <= str.length else { return nil }

        // 长名字优先匹配，避免「小明」抢了「小明妈妈」
        for sheet in doc.cardSheets {
            let name = (sheet.card?.name.isEmpty == false ? sheet.card!.name : sheet.title)
                .trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { continue }
            var search = NSRange(location: 0, length: str.length)
            while search.length > 0 {
                let r = str.range(of: name, options: [], range: search)
                if r.location == NSNotFound { break }
                if r.location <= idx && idx < r.location + r.length {
                    let screen = textView.firstRect(forCharacterRange: r, actualRange: nil)
                    return (sheet, screen)
                }
                let next = r.location + max(1, r.length)
                if next >= str.length { break }
                search = NSRange(location: next, length: str.length - next)
            }
        }
        return nil
    }

    /// 返回 true 表示这次点击被卡片消费掉（不再交给文本选择）
    func handleCardClick(at point: NSPoint) -> Bool {
        guard let (sheet, screenRect) = cardAt(point: point), let card = sheet.card else { return false }
        showCardPopover(card, subtitle: card.relation, in: screenRect)
        return true
    }

    func showCardPopover(_ card: CardData, subtitle: String, in screenRect: NSRect) {
        let pop = NSPopover()
        pop.behavior = .transient
        pop.animates = true

        let box = FlippedStackView(frame: NSRect(x: 0, y: 0, width: 280, height: 10))
        box.wantsLayer = true
        let preset = ThemePresets.preset(doc.theme)
        box.layer?.backgroundColor = preset.bg.cgColor

        var y: CGFloat = 0
        func line(_ text: String, size: CGFloat, weight: NSFont.Weight, alpha: CGFloat) -> CGFloat {
            let attr: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: size, weight: weight),
                .foregroundColor: preset.text.withAlphaComponent(alpha),
            ]
            let w: CGFloat = 250
            let fit = (text as NSString).boundingRect(
                with: NSSize(width: w, height: 999),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: attr)
            let h = max(16, ceil(fit.height) + 2)
            let label = NSTextField(wrappingLabelWithString: text)
            label.font = NSFont.systemFont(ofSize: size, weight: weight)
            label.textColor = preset.text.withAlphaComponent(alpha)
            label.frame = NSRect(x: 14, y: y, width: w, height: h)
            label.isBordered = false
            label.drawsBackground = false
            box.addSubview(label)
            y += h + 6
            return h
        }

        _ = line(card.name.isEmpty ? "未命名" : card.name, size: 15, weight: .semibold, alpha: 1)
        if !card.relation.isEmpty { _ = line("关系：" + card.relation, size: 12, weight: .regular, alpha: 0.75) }
        if !card.appearance.isEmpty { _ = line("外貌：" + card.appearance, size: 12, weight: .regular, alpha: 0.75) }
        if !card.catchphrase.isEmpty { _ = line("「" + card.catchphrase + "」", size: 12.5, weight: .regular, alpha: 0.9) }
        box.frame.size.height = max(46, y + 6)

        let vc = NSViewController()
        vc.view = box
        pop.contentViewController = vc
        pop.contentSize = box.frame.size
        pop.show(relativeTo: screenRect, of: textView, preferredEdge: .maxY)
    }
}
