import AppKit

// MARK: - 阅读模式
//
// 改稿和写稿是两种状态。写的时候要工具栏、要侧栏；读的时候这些东西全是噪音。
// 所以阅读模式只做三件事：
//   1. 把所有控件藏起来，正文收成居中一条（约 720pt）
//   2. 正文设成只读（避免手滑改坏）
//   3. ← → 直接翻篇，Esc 退出——通读时不用去点侧栏

extension EditorRoot {

    /// 阅读顺序：按侧栏树的顺序把文稿排成一条（人物卡不算）
    func readingOrder() -> [Sheet] {
        var out: [Sheet] = []
        func walk(_ parent: String?) {
            for f in doc.childFolders(of: parent) { walk(f.id) }
            for s in doc.sheets(in: parent) where s.card == nil { out.append(s) }
        }
        walk(nil)
        return out
    }

    @objc func toggleReading(_ sender: Any?) {
        readingMode.toggle()
        applyReadingMode()
    }

    @objc func nextSheetInReading(_ sender: Any?) { stepReading(1) }
    @objc func prevSheetInReading(_ sender: Any?) { stepReading(-1) }

    func stepReading(_ delta: Int) {
        let order = readingOrder()
        guard order.count > 1, let i = order.firstIndex(where: { $0.id == doc.activeId }) else { return }
        let j = min(order.count - 1, max(0, i + delta))
        guard j != i else { return }
        switchTo(order[j].id)
        // switchTo 会把光标放到末尾；读的时候要从头看
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.textView.setSelectedRange(NSRange(location: 0, length: 0))
            self.textView.scroll(NSPoint(x: 0, y: -self.textView.textContainerInset.height))
        }
    }

    func applyReadingMode() {
        let on = readingMode
        if on {
            readingWasSidebarVisible = doc.sidebarVisible
            doc.sidebarVisible = false
        } else {
            doc.sidebarVisible = readingWasSidebarVisible
        }
        applySidebarVisibility(animated: true)

        toolStack.isHidden = on
        titleInput.isHidden = on
        searchField.isHidden = on
        plusButton.isHidden = on
        folderButton.isHidden = on
        barLabel.isHidden = on
        sidebarFooter.isHidden = on

        textView.isEditable = !on
        textView.isSelectable = true

        if on { installReadingChrome() }
        readingExitButton?.isHidden = !on
        readingHint?.isHidden = !on

        if on { installReadingMonitor() } else { removeReadingMonitor() }

        updateTextInsets()
        applyMarkdownStyling()
        textView.typingAttributes = bodyAttributes
        persistNow()
    }

    private func installReadingChrome() {
        if readingExitButton == nil {
            let b = NSButton(title: "✕ 退出阅读", target: self, action: Selector(("toggleReading:")))
            b.bezelStyle = .texturedRounded
            b.controlSize = .small
            b.font = NSFont.systemFont(ofSize: 11)
            b.translatesAutoresizingMaskIntoConstraints = false
            addSubview(b)
            NSLayoutConstraint.activate([
                b.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
                b.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            ])
            readingExitButton = b

            let h = NSTextField(labelWithString: "← → 翻篇　·　Esc 退出阅读")
            h.font = NSFont.systemFont(ofSize: 11)
            h.textColor = .tertiaryLabelColor
            h.alignment = .center
            h.translatesAutoresizingMaskIntoConstraints = false
            addSubview(h)
            NSLayoutConstraint.activate([
                h.centerXAnchor.constraint(equalTo: centerXAnchor),
                h.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),
            ])
            readingHint = h
        }
    }

    private func installReadingMonitor() {
        guard readingMonitor == nil else { return }
        readingMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            guard let self = self, self.readingMode else { return e }
            switch e.keyCode {
            case 123: self.stepReading(-1); return nil   // ←
            case 124: self.stepReading(1); return nil    // →
            case 53:  self.toggleReading(nil); return nil // Esc
            default:  return e
            }
        }
    }

    private func removeReadingMonitor() {
        if let m = readingMonitor { NSEvent.removeMonitor(m); readingMonitor = nil }
    }
}
