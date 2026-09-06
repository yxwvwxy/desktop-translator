import AppKit
import WidgetKit

final class TranslatorViewController: NSViewController, NSTextViewDelegate, NSTableViewDataSource, NSTableViewDelegate {
    private var source: Language = .en
    private var target: Language = .zh
    private var debounceWork: DispatchWorkItem?
    private var translateGeneration = 0
    private var lastPlainText = ""
    private var history: [HistoryItem] = SearchHistory.items()

    private let titleLabel = NSTextField(labelWithString: "Desktop Translator")
    private let subtitleLabel = NSTextField(labelWithString: "Dictionary, slang, and examples")
    private let sourceButton = NSPopUpButton()
    private let targetButton = NSPopUpButton()
    private let swapButton = NSButton()
    private let pasteButton = NSButton()
    private let clearButton = NSButton()
    private let translateButton = NSButton()
    private let copyButton = NSButton()
    private let countLabel = NSTextField(labelWithString: "0 chars")
    private let hintLabel = NSTextField(labelWithString: "⌘↩ Look up    ⌘C or Ctrl+C copy")
    private let inputScroll = NSScrollView()
    private let outputScroll = NSScrollView()
    private let historyScroll = NSScrollView()
    private let historyTable = NSTableView()
    private let historyLabel = NSTextField(labelWithString: "Recent")
    private var historyHeightConstraint: NSLayoutConstraint?
    private let inputView = NSTextView()
    private let outputView = NSTextView()
    private let spinner = NSProgressIndicator()

    override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 480, height: 840))
        root.wantsLayer = true
        root.layer?.backgroundColor = Theme.paper.cgColor
        view = root
        buildInterface()
        showPlaceholder()
        updateDirectionLabel()
        refreshHistoryLabel()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(icloudHistoryChanged),
            name: SearchHistory.didChange,
            object: nil
        )
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        view.window?.makeFirstResponder(inputView)
        reloadHistory()
    }

    @objc private func icloudHistoryChanged() {
        history = SearchHistory.items()
        historyTable.reloadData()
        historyHeightConstraint?.constant = historyHeight(for: history.count)
        refreshHistoryLabel()
    }

    private func buildInterface() {
        titleLabel.font = NSFont(name: "Iowan Old Style", size: 22) ?? .systemFont(ofSize: 22, weight: .semibold)
        titleLabel.textColor = Theme.ink
        subtitleLabel.font = .systemFont(ofSize: 12)
        subtitleLabel.textColor = Theme.muted

        configureIconButton(swapButton, title: "⇄", action: #selector(swapLanguages))
        configureIconButton(pasteButton, title: "Paste", action: #selector(pasteInput))
        configureIconButton(clearButton, title: "Clear", action: #selector(clearAll))

        sourceButton.removeAllItems()
        sourceButton.addItems(withTitles: Language.allCases.map(\.label))
        sourceButton.selectItem(withTitle: Language.en.label)
        sourceButton.target = self
        sourceButton.action = #selector(sourceChanged)

        targetButton.removeAllItems()
        targetButton.addItems(withTitles: Language.allCases.map(\.label))
        targetButton.selectItem(withTitle: Language.zh.label)
        targetButton.target = self
        targetButton.action = #selector(targetChanged)

        configureTextView(inputView, editable: true)
        configureTextView(outputView, editable: false)
        embed(inputView, in: inputScroll)
        embed(outputView, in: outputScroll)
        configureHistoryTable()

        countLabel.font = .systemFont(ofSize: 11)
        countLabel.textColor = Theme.muted
        hintLabel.font = .systemFont(ofSize: 11)
        hintLabel.textColor = Theme.muted

        copyButton.title = "Copy"
        copyButton.bezelStyle = .rounded
        copyButton.target = self
        copyButton.action = #selector(copyOutput)

        translateButton.title = "Look up"
        translateButton.bezelStyle = .rounded
        translateButton.setButtonType(.momentaryPushIn)
        translateButton.target = self
        translateButton.action = #selector(translateNow)
        translateButton.keyEquivalent = "\r"
        translateButton.keyEquivalentModifierMask = .command
        translateButton.contentTintColor = Theme.seal

        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isDisplayedWhenStopped = false

        let seal = SealView(frame: NSRect(x: 22, y: 780, width: 38, height: 38))
        let inputLabel = makeCaption("Word or phrase")
        let outputLabel = makeCaption("Entry")
        historyLabel.font = .systemFont(ofSize: 12, weight: .medium)
        historyLabel.textColor = Theme.muted

        [titleLabel, subtitleLabel, sourceButton, targetButton, swapButton, pasteButton, clearButton,
         translateButton, copyButton, countLabel, hintLabel, inputScroll, outputScroll, historyScroll,
         spinner, seal, inputLabel, outputLabel, historyLabel].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview($0)
        }

        NSLayoutConstraint.activate([
            seal.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 22),
            seal.topAnchor.constraint(equalTo: view.topAnchor, constant: 20),
            seal.widthAnchor.constraint(equalToConstant: 38),
            seal.heightAnchor.constraint(equalToConstant: 38),

            titleLabel.leadingAnchor.constraint(equalTo: seal.trailingAnchor, constant: 10),
            titleLabel.topAnchor.constraint(equalTo: seal.topAnchor, constant: -2),
            subtitleLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 1),

            sourceButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 22),
            sourceButton.topAnchor.constraint(equalTo: seal.bottomAnchor, constant: 18),
            sourceButton.widthAnchor.constraint(equalToConstant: 112),

            swapButton.leadingAnchor.constraint(equalTo: sourceButton.trailingAnchor, constant: 8),
            swapButton.centerYAnchor.constraint(equalTo: sourceButton.centerYAnchor),
            swapButton.widthAnchor.constraint(equalToConstant: 44),

            targetButton.leadingAnchor.constraint(equalTo: swapButton.trailingAnchor, constant: 8),
            targetButton.centerYAnchor.constraint(equalTo: sourceButton.centerYAnchor),
            targetButton.widthAnchor.constraint(equalToConstant: 112),

            pasteButton.trailingAnchor.constraint(equalTo: clearButton.leadingAnchor, constant: -6),
            pasteButton.centerYAnchor.constraint(equalTo: sourceButton.centerYAnchor),
            clearButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -22),
            clearButton.centerYAnchor.constraint(equalTo: sourceButton.centerYAnchor),

            inputLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 22),
            inputLabel.topAnchor.constraint(equalTo: sourceButton.bottomAnchor, constant: 16),
            countLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -22),
            countLabel.centerYAnchor.constraint(equalTo: inputLabel.centerYAnchor),

            inputScroll.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 22),
            inputScroll.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -22),
            inputScroll.topAnchor.constraint(equalTo: inputLabel.bottomAnchor, constant: 6),
            inputScroll.heightAnchor.constraint(equalToConstant: 88),

            outputLabel.leadingAnchor.constraint(equalTo: inputLabel.leadingAnchor),
            outputLabel.topAnchor.constraint(equalTo: inputScroll.bottomAnchor, constant: 14),
            spinner.leadingAnchor.constraint(equalTo: outputLabel.trailingAnchor, constant: 8),
            spinner.centerYAnchor.constraint(equalTo: outputLabel.centerYAnchor),
            copyButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -22),
            copyButton.centerYAnchor.constraint(equalTo: outputLabel.centerYAnchor),

            outputScroll.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 22),
            outputScroll.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -22),
            outputScroll.topAnchor.constraint(equalTo: outputLabel.bottomAnchor, constant: 6),
            outputScroll.bottomAnchor.constraint(equalTo: historyLabel.topAnchor, constant: -12),

            historyLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 22),
            historyLabel.bottomAnchor.constraint(equalTo: historyScroll.topAnchor, constant: -6),

            historyScroll.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 22),
            historyScroll.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -22),
            historyScroll.bottomAnchor.constraint(equalTo: hintLabel.topAnchor, constant: -12),

            hintLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 22),
            hintLabel.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -16),
            translateButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -22),
            translateButton.centerYAnchor.constraint(equalTo: hintLabel.centerYAnchor),
        ])
    }

    private func makeCaption(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.textColor = Theme.muted
        return label
    }

    private func configureIconButton(_ button: NSButton, title: String, action: Selector) {
        button.title = title
        button.bezelStyle = .rounded
        button.target = self
        button.action = action
    }

    private func configureTextView(_ textView: NSTextView, editable: Bool) {
        textView.delegate = self
        textView.isEditable = editable
        textView.isSelectable = true
        textView.isRichText = !editable
        textView.font = .systemFont(ofSize: 16)
        textView.textColor = Theme.ink
        textView.backgroundColor = Theme.panel
        textView.insertionPointColor = Theme.seal
        textView.textContainerInset = NSSize(width: 10, height: 10)
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.textContainer?.widthTracksTextView = true
        textView.drawsBackground = true
    }

    private func embed(_ textView: NSTextView, in scroll: NSScrollView) {
        scroll.hasVerticalScroller = true
        scroll.borderType = .lineBorder
        scroll.backgroundColor = Theme.panel
        scroll.drawsBackground = true
        scroll.documentView = textView
        scroll.wantsLayer = true
        scroll.layer?.cornerRadius = 8
        scroll.layer?.borderWidth = 1
        scroll.layer?.borderColor = Theme.line.cgColor
        textView.minSize = NSSize(width: 0, height: 80)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.autoresizingMask = [.width]
    }

    private func configureHistoryTable() {
        let queryColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("query"))
        queryColumn.title = "Query"
        queryColumn.minWidth = 120
        queryColumn.width = 180

        let translationColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("translation"))
        translationColumn.title = "Translation"
        translationColumn.minWidth = 120
        translationColumn.width = 200

        let deleteColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("delete"))
        deleteColumn.title = ""
        deleteColumn.minWidth = 36
        deleteColumn.maxWidth = 40
        deleteColumn.width = 38

        historyTable.addTableColumn(queryColumn)
        historyTable.addTableColumn(translationColumn)
        historyTable.addTableColumn(deleteColumn)
        historyTable.headerView = NSTableHeaderView()
        historyTable.dataSource = self
        historyTable.delegate = self
        historyTable.rowHeight = 26
        historyTable.backgroundColor = Theme.panel
        historyTable.usesAlternatingRowBackgroundColors = true
        historyTable.allowsEmptySelection = true
        historyTable.allowsMultipleSelection = false
        historyTable.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        historyTable.target = self
        historyTable.action = #selector(historyRowClicked)
        historyTable.doubleAction = #selector(historyRowClicked)

        historyScroll.hasVerticalScroller = true
        historyScroll.borderType = .lineBorder
        historyScroll.backgroundColor = Theme.panel
        historyScroll.drawsBackground = true
        historyScroll.documentView = historyTable
        historyScroll.wantsLayer = true
        historyScroll.layer?.cornerRadius = 8
        historyScroll.layer?.borderWidth = 1
        historyScroll.layer?.borderColor = Theme.line.cgColor
        let height = historyScroll.heightAnchor.constraint(equalToConstant: historyHeight(for: history.count))
        height.isActive = true
        historyHeightConstraint = height
        refreshHistoryLabel()
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        history.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard history.indices.contains(row) else { return nil }
        let identifier = tableColumn?.identifier ?? NSUserInterfaceItemIdentifier("query")
        if identifier.rawValue == "delete" {
            let button = NSButton(title: "✕", target: self, action: #selector(deleteHistory(_:)))
            button.bezelStyle = .inline
            button.isBordered = false
            button.font = .systemFont(ofSize: 12, weight: .semibold)
            button.contentTintColor = Theme.seal
            button.tag = row
            button.toolTip = "Delete this record"
            return button
        }

        let item = history[row]
        let text = identifier.rawValue == "translation" ? item.translation : item.query
        let cell = tableView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView
            ?? makeHistoryCell(identifier: identifier)
        cell.textField?.stringValue = collapsed(text)
        return cell
    }

    private func makeHistoryCell(identifier: NSUserInterfaceItemIdentifier) -> NSTableCellView {
        let cell = NSTableCellView()
        cell.identifier = identifier
        let field = NSTextField(labelWithString: "")
        field.font = .systemFont(ofSize: 12)
        field.textColor = Theme.ink
        field.lineBreakMode = .byTruncatingTail
        field.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(field)
        cell.textField = field
        NSLayoutConstraint.activate([
            field.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 6),
            field.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -6),
            field.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        return cell
    }

    private func collapsed(_ text: String) -> String {
        text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }

    @objc private func historyRowClicked() {
        let row = historyTable.clickedRow
        let column = historyTable.clickedColumn
        guard history.indices.contains(row) else { return }
        if column >= 0, historyTable.tableColumns[column].identifier.rawValue == "delete" {
            return
        }
        inputView.string = history[row].query
        countLabel.stringValue = "\(history[row].query.count) chars"
        updateDirectionLabel()
        startLookup()
    }

    @objc private func deleteHistory(_ sender: NSButton) {
        let row = sender.tag
        guard history.indices.contains(row) else { return }
        SearchHistory.remove(at: row)
        reloadHistory()
    }

    private func recordHistory(query: String, translation: String) {
        SearchHistory.add(query: query, translation: translation)
        reloadHistory()
    }

    private func reloadHistory() {
        history = SearchHistory.items()
        historyTable.reloadData()
        historyHeightConstraint?.constant = historyHeight(for: history.count)
        refreshHistoryLabel()
        WidgetCenter.shared.reloadAllTimelines()
    }

    private func historyHeight(for count: Int) -> CGFloat {
        let header: CGFloat = 28
        let row: CGFloat = 26
        let visible = max(count, 1)
        return min(header + CGFloat(visible) * row + 8, 360)
    }

    private func refreshHistoryLabel() {
        historyLabel.stringValue = history.isEmpty ? "Recent" : "Recent · \(history.count)"
    }

    func textDidChange(_ notification: Notification) {
        guard notification.object as? NSTextView === inputView else { return }
        let count = inputView.string.replacingOccurrences(of: "\\s+", with: "", options: .regularExpression).count
        countLabel.stringValue = count == 1 ? "1 char" : "\(count) chars"
        updateDirectionLabel()
        debounceWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.startLookup()
        }
        debounceWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7, execute: work)
    }

    @objc private func sourceChanged() {
        source = Language.allCases[sourceButton.indexOfSelectedItem]
        if source == target {
            target = source == .zh ? .en : .zh
            targetButton.selectItem(withTitle: target.label)
        }
        updateDirectionLabel()
        startLookup()
    }

    @objc private func targetChanged() {
        target = Language.allCases[targetButton.indexOfSelectedItem]
        if source == target {
            source = target == .zh ? .en : .zh
            sourceButton.selectItem(withTitle: source.label)
        }
        updateDirectionLabel()
        startLookup()
    }

    @objc private func swapLanguages() {
        swap(&source, &target)
        sourceButton.selectItem(withTitle: source.label)
        targetButton.selectItem(withTitle: target.label)
        updateDirectionLabel()
        startLookup()
    }

    @objc private func pasteInput() {
        guard let text = NSPasteboard.general.string(forType: .string), !text.isEmpty else { return }
        inputView.string = text
        textDidChange(Notification(name: NSText.didChangeNotification, object: inputView))
    }

    @objc private func clearAll() {
        debounceWork?.cancel()
        translateGeneration += 1
        inputView.string = ""
        lastPlainText = ""
        countLabel.stringValue = "0 chars"
        spinner.stopAnimation(nil)
        showPlaceholder()
        updateDirectionLabel()
    }

    @objc private func copyOutput() {
        let text = lastPlainText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        copyButton.title = "Copied"
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.copyButton.title = "Copy"
        }
    }

    @objc private func translateNow() {
        debounceWork?.cancel()
        startLookup()
    }

    private func updateDirectionLabel() {
        subtitleLabel.stringValue = "\(source.label) → \(target.label)"
    }

    private func showPlaceholder() {
        outputView.textStorage?.setAttributedString(EntryRenderer.placeholder())
    }

    private func startLookup() {
        let text = inputView.string
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            lastPlainText = ""
            showPlaceholder()
            return
        }

        translateGeneration += 1
        let generation = translateGeneration
        let currentSource = source
        let currentTarget = target
        spinner.startAnimation(nil)

        Task {
            do {
                let entry = try await DictionaryService.lookup(text, from: currentSource, to: currentTarget)
                await MainActor.run {
                    guard generation == self.translateGeneration else { return }
                    self.lastPlainText = entry.plainText
                    self.outputView.textStorage?.setAttributedString(EntryRenderer.render(entry))
                    self.recordHistory(query: entry.query, translation: entry.translation)
                    self.spinner.stopAnimation(nil)
                }
            } catch {
                await MainActor.run {
                    guard generation == self.translateGeneration else { return }
                    let message = (error as? LocalizedError)?.errorDescription ?? TranslatorError.failed.errorDescription ?? "Lookup failed."
                    self.lastPlainText = ""
                    self.outputView.textStorage?.setAttributedString(EntryRenderer.error(message))
                    self.spinner.stopAnimation(nil)
                }
            }
        }
    }
}

final class SealView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        Theme.seal.setStroke()
        let outer = bounds.insetBy(dx: 1, dy: 1)
        let inner = bounds.insetBy(dx: 4, dy: 4)
        let outerPath = NSBezierPath(roundedRect: outer, xRadius: 6, yRadius: 6)
        outerPath.lineWidth = 1
        outerPath.stroke()
        let innerPath = NSBezierPath(roundedRect: inner, xRadius: 4, yRadius: 4)
        innerPath.lineWidth = 1.4
        innerPath.stroke()

        let text = "Aa" as NSString
        let font = NSFont(name: "Iowan Old Style", size: 16)
            ?? NSFont.systemFont(ofSize: 15, weight: .semibold)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: Theme.seal,
        ]
        let size = text.size(withAttributes: attributes)
        let point = NSPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2 + 1)
        text.draw(at: point, withAttributes: attributes)
    }
}
