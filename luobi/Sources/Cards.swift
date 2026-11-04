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
    /// 选中一段文字后右键「用这段文字建人物卡」
    var cardCreateHandler: ((String) -> Void)?

    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.command) {
            let p = convert(event.locationInWindow, from: nil)
            if cardClickHandler?(p) == true { return }
        }
        super.mouseDown(with: event)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let m = super.menu(for: event) ?? NSMenu()
        let selected = (string as NSString).substring(with: selectedRange())
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !selected.isEmpty, !selected.contains("\n") {
            let shown = selected.count > 8 ? String(selected.prefix(8)) + "…" : selected
            m.addItem(.separator())
            let item = NSMenuItem(title: "用「\(shown)」建人物卡", action: #selector(createCardFromSelection(_:)), keyEquivalent: "")
            item.target = self
            m.addItem(item)
        }
        return m
    }

    @objc private func createCardFromSelection(_ sender: Any?) {
        let selected = (string as NSString).substring(with: selectedRange())
            .trimmingCharacters(in: .whitespacesAndNewlines)
        cardCreateHandler?(selected)
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

        let name = card.name.isEmpty ? "" : card.name
        let mentions = doc.mentions(of: name)
        if !mentions.isEmpty {
            _ = line("出场 \(mentions.count) 章 · 共 \(mentions.reduce(0) { $0 + $1.count }) 次", size: 11.5, weight: .regular, alpha: 0.55)
            let btn = NSButton(title: "看出场章节", target: self, action: #selector(showMentionsFromPopover(_:)))
            btn.bezelStyle = .texturedRounded
            btn.controlSize = .small
            btn.font = NSFont.systemFont(ofSize: 11)
            btn.identifier = NSUserInterfaceItemIdentifier(name)
            btn.frame = NSRect(x: 14, y: y, width: 110, height: 22)
            box.addSubview(btn)
            y += 28
        }
        box.frame.size.height = max(46, y + 6)

        let vc = NSViewController()
        vc.view = box
        pop.contentViewController = vc
        pop.contentSize = box.frame.size
        pop.show(relativeTo: screenRect, of: textView, preferredEdge: .maxY)
    }
}

// MARK: - 选中文字建卡 + 人物一览

/// 一览里的一行：整行可点
final class CardRowView: NSView {
    var onClick: (() -> Void)?
    override func mouseDown(with event: NSEvent) { onClick?() }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .pointingHand) }
}

extension EditorRoot {

    /// 正文右键「用「X」建人物卡」的落点：校验 → 建卡 → 直接打开编辑面板
    func handleCreateCard(from raw: String) {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        guard name.count <= 12 else {
            startupNote = "选中的文字太长（上限 12 字），先选名字本身"
            refreshBar()
            return
        }
        if doc.cardSheet(named: name) != nil {
            startupNote = "已经有「\(name)」这张卡了"
            refreshBar()
            return
        }
        let folder = doc.sheet(id: doc.activeId)?.folderId
        let s = Sheet(id: UUID().uuidString, title: name, content: "",
                      updatedAt: Date().timeIntervalSince1970, folderId: folder,
                      card: CardData(name: name))
        doc.sheets.append(s)
        doc.activeId = s.id
        refreshTable()
        persistNow()
        switchTo(s.id)
        editCard(id: s.id)
    }

    /// 所有卡片按分组归拢，用于「人物一览」
    func cardsGrouped() -> [(String, [Sheet])] {
        var out: [(String, [Sheet])] = []
        func walk(_ parent: String?, path: String) {
            for f in doc.childFolders(of: parent) {
                let list = doc.sheets(in: f.id).filter { $0.card != nil }
                let label = path.isEmpty ? f.name : path + " / " + f.name
                if !list.isEmpty { out.append((label, list)) }
                walk(f.id, path: label)
            }
        }
        walk(nil, path: "")
        let loose = doc.sheets(in: nil).filter { $0.card != nil }
        if !loose.isEmpty { out.append(("未归组", loose)) }
        return out
    }

    @objc func showCardsOverview(_ sender: Any?) {
        let groups = cardsGrouped()
        let panel = LuobiSheetPanel(contentRect: NSRect(x: 0, y: 0, width: 680, height: 520),
                            styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        panel.title = "人物一览 · \(doc.cardSheets.count) 张"
        panel.isReleasedWhenClosed = false
        let preset = ThemePresets.preset(doc.theme)
        panel.backgroundColor = preset.bg

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false

        if groups.isEmpty {
            let tip = NSTextField(labelWithString: "还没有人物卡片。\n在正文里选中一个名字 → 右键 → 建人物卡，或菜单「文件 → 新建人物卡」。")
            tip.font = NSFont.systemFont(ofSize: 13)
            tip.textColor = preset.text.withAlphaComponent(0.7)
            tip.maximumNumberOfLines = 0
            stack.addArrangedSubview(tip)
        }

        for (label, list) in groups {
            let head = NSTextField(labelWithString: label)
            head.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
            head.textColor = preset.text.withAlphaComponent(0.55)
            stack.addArrangedSubview(head)
            for s in list {
                let row = CardRowView()
                row.wantsLayer = true
                row.translatesAutoresizingMaskIntoConstraints = false
                row.onClick = { [weak self, weak panel] in
                    guard let self = self else { return }
                    self.doc.activeId = s.id
                    self.refreshTable()
                    self.switchTo(s.id)
                    if let r = self.row(forID: s.id) {
                        self.table.selectRowIndexes(IndexSet(integer: r), byExtendingSelection: false)
                    }
                    panel?.close()
                }

                let icon = NSImageView()
                icon.image = NSImage(systemSymbolName: "person.crop.circle", accessibilityDescription: "人物")
                icon.translatesAutoresizingMaskIntoConstraints = false
                let nm = NSTextField(labelWithString: (s.card?.name.isEmpty == false ? s.card!.name : s.title))
                nm.font = NSFont.systemFont(ofSize: 13.5, weight: .medium)
                nm.textColor = preset.text
                nm.translatesAutoresizingMaskIntoConstraints = false
                let rel = NSTextField(labelWithString: s.card?.relation ?? "")
                rel.font = NSFont.systemFont(ofSize: 11.5)
                rel.textColor = preset.text.withAlphaComponent(0.6)
                rel.translatesAutoresizingMaskIntoConstraints = false
                rel.lineBreakMode = .byTruncatingTail

                row.addSubview(icon); row.addSubview(nm); row.addSubview(rel)
                NSLayoutConstraint.activate([
                    row.widthAnchor.constraint(equalToConstant: 600),
                    row.heightAnchor.constraint(equalToConstant: 34),
                    icon.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 6),
                    icon.centerYAnchor.constraint(equalTo: row.centerYAnchor),
                    icon.widthAnchor.constraint(equalToConstant: 16),
                    icon.heightAnchor.constraint(equalToConstant: 16),
                    nm.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 8),
                    nm.centerYAnchor.constraint(equalTo: row.centerYAnchor),
                    rel.leadingAnchor.constraint(equalTo: nm.trailingAnchor, constant: 10),
                    rel.trailingAnchor.constraint(lessThanOrEqualTo: row.trailingAnchor, constant: -8),
                    rel.centerYAnchor.constraint(equalTo: row.centerYAnchor),
                ])
                stack.addArrangedSubview(row)
            }
        }

        // 滚动视图默认原点在左下，套一层 flipped 容器，内容才会从顶部开始排
        let container = FlippedStackView()
        container.wantsLayer = true
        container.layer?.backgroundColor = preset.bg.cgColor
        container.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stack)
        scroll.documentView = container
        scroll.backgroundColor = preset.bg
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 16),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: container.bottomAnchor, constant: -16),
            container.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
            container.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
            container.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
            container.heightAnchor.constraint(greaterThanOrEqualTo: scroll.contentView.heightAnchor),
        ])
        let wrap = wrapWithFooter(scroll)
        wrap.frame = panel.contentLayoutRect
        wrap.autoresizingMask = [.width, .height]
        panel.contentView = wrap
        panel.onEsc = { [weak panel] in panel?.closeSelf() }

        presentSheet(panel)
    }
}


// MARK: - 出场索引（人物的反向链接）

extension EditorRoot {

    @objc func showMentionsFromPopover(_ sender: Any?) {
        guard let name = (sender as? NSButton)?.identifier?.rawValue else { return }
        showMentions(named: name)
    }

    @objc func showMentionsForContextCard(_ sender: Any?) {
        guard let it = contextSideItem(), let s = it.sheet, let c = s.card else { return }
        showMentions(named: c.name.isEmpty ? s.title : c.name)
    }

    /// 「这个名字在哪些章节出现过」——点一行就跳到那一处
    func showMentions(named raw: String) {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let list = doc.mentions(of: name)
        let preset = ThemePresets.preset(doc.theme)

        let panel = LuobiSheetPanel(contentRect: NSRect(x: 0, y: 0, width: 560, height: 440),
                            styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        panel.title = "\(name) · 出场章节"
        panel.isReleasedWhenClosed = false

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.backgroundColor = preset.bg
        scroll.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false

        let head = NSTextField(labelWithString: list.isEmpty
                               ? "正文里还没有出现过「\(name)」。"
                               : "共 \(list.count) 章 / \(list.reduce(0) { $0 + $1.count }) 次，点一行跳到那一处：")
        head.font = NSFont.systemFont(ofSize: 12)
        head.textColor = preset.text.withAlphaComponent(0.6)
        stack.addArrangedSubview(head)

        for m in list {
            let row = CardRowView()
            row.wantsLayer = true
            row.translatesAutoresizingMaskIntoConstraints = false
            row.onClick = { [weak self, weak panel] in
                guard let self = self else { return }
                self.switchTo(m.sheetId)
                self.jump(to: m.firstRange)
                panel?.close()
            }
            let t = NSTextField(labelWithString: m.title.isEmpty ? "未命名" : m.title)
            t.font = NSFont.systemFont(ofSize: 13)
            t.textColor = preset.text
            t.lineBreakMode = .byTruncatingTail
            t.translatesAutoresizingMaskIntoConstraints = false
            let n = NSTextField(labelWithString: "\(m.count) 次")
            n.font = NSFont.systemFont(ofSize: 11.5)
            n.textColor = preset.text.withAlphaComponent(0.55)
            n.translatesAutoresizingMaskIntoConstraints = false
            row.addSubview(t); row.addSubview(n)
            NSLayoutConstraint.activate([
                row.widthAnchor.constraint(equalToConstant: 480),
                row.heightAnchor.constraint(equalToConstant: 30),
                t.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 6),
                t.centerYAnchor.constraint(equalTo: row.centerYAnchor),
                t.trailingAnchor.constraint(lessThanOrEqualTo: n.leadingAnchor, constant: -10),
                n.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -6),
                n.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            ])
            stack.addArrangedSubview(row)
        }

        let container = FlippedStackView()
        container.wantsLayer = true
        container.layer?.backgroundColor = preset.bg.cgColor
        container.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stack)
        scroll.documentView = container
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 16),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: container.bottomAnchor, constant: -16),
            container.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
            container.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
            container.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
            container.heightAnchor.constraint(greaterThanOrEqualTo: scroll.contentView.heightAnchor),
        ])
        let wrap2 = wrapWithFooter(scroll)
        wrap2.frame = panel.contentLayoutRect
        wrap2.autoresizingMask = [.width, .height]
        panel.contentView = wrap2
        panel.onEsc = { [weak panel] in panel?.closeSelf() }

        presentSheet(panel)
    }
}
