import AppKit
import WidgetKit

final class TranslatorViewController: NSViewController, NSTextViewDelegate, NSTableViewDataSource, NSTableViewDelegate, NSSplitViewDelegate {
    private var source: Language = .en
    private var target: Language = .zh
    private var sourceIsAuto = true
    private var debounceWork: DispatchWorkItem?
    private var translateGeneration = 0
    private var history: [HistoryItem] = SearchHistory.items()

    private let titleLabel = NSTextField(labelWithString: "Desktop Translator")
    private let subtitleLabel = NSTextField(labelWithString: "English and Chinese")
    private let sourceButton = NSPopUpButton()
    private let targetButton = NSPopUpButton()
    private let swapButton = NSButton()
    private let clearButton = NSButton()
    private let inputScroll = NSScrollView()
    private let outputScroll = NSScrollView()
    private let historyScroll = NSScrollView()
    private let historyTable = NSTableView()
    private let historyLabel = NSTextField(labelWithString: "Recent")
    private var ignoreNextHistoryClick = false
    private let lookupSplit = PaneSplitView()
    private let inputPane = NSView()
    private let outputPane = NSView()
    private let historyPane = NSView()
    private let inputLabel = NSTextField(labelWithString: "Entry")
    private let outputLabel = NSTextField(labelWithString: "Translation")
    private var didSetSplitPosition = false
    private let splitAutosaveName = "DesktopTranslator.mainSplit.v4"
    private let entryMinHeight: CGFloat = 70
    private let translationMinHeight: CGFloat = 90
    private let recentMinHeight: CGFloat = 120
    private let inputView = NSTextView()
    private let outputView = NSTextView()
    private let spinner = NSProgressIndicator()

    override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 500, height: 800))
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
        inputView.isContinuousSpellCheckingEnabled = true
        reloadHistory()
        applyDefaultSplitIfNeeded()
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        applyDefaultSplitIfNeeded()
        layoutHistoryColumns()
    }

    private func layoutHistoryColumns() {
        guard historyTable.tableColumns.count == 2 else { return }
        let available = historyScroll.documentVisibleRect.width
        guard available > 200 else { return }
        historyTable.tableColumns[0].width = min(max(available * 0.32, 80), available - 160)
        historyTable.sizeLastColumnToFit()
    }

    @objc private func icloudHistoryChanged() {
        history = SearchHistory.items()
        historyTable.reloadData()
        refreshHistoryLabel()
    }

    private func buildInterface() {
        titleLabel.font = NSFont(name: "Iowan Old Style", size: 22) ?? .systemFont(ofSize: 22, weight: .semibold)
        titleLabel.textColor = Theme.ink
        subtitleLabel.font = .systemFont(ofSize: 12)
        subtitleLabel.textColor = Theme.muted

        configureIconButton(swapButton, title: "⇄", action: #selector(swapLanguages))
        configureIconButton(clearButton, title: "Clear", action: #selector(clearAll))

        sourceButton.removeAllItems()
        sourceButton.addItem(withTitle: "Auto")
        sourceButton.addItems(withTitles: Language.allCases.map(\.label))
        sourceButton.selectItem(at: 0)
        sourceButton.target = self
        sourceButton.action = #selector(sourceChanged)
        sourceButton.setContentCompressionResistancePriority(.required, for: .horizontal)

        targetButton.removeAllItems()
        targetButton.addItems(withTitles: Language.allCases.map(\.label))
        targetButton.selectItem(withTitle: Language.zh.label)
        targetButton.target = self
        targetButton.action = #selector(targetChanged)
        targetButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        clearButton.setContentCompressionResistancePriority(.required, for: .horizontal)

        configureTextView(inputView, editable: true)
        configureTextView(outputView, editable: false)
        embed(inputView, in: inputScroll)
        embed(outputView, in: outputScroll)
        configureLookupSplit()
        configureHistoryTable()

        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isDisplayedWhenStopped = false

        let seal = SealView(frame: NSRect(x: 22, y: 720, width: 38, height: 38))
        styleCaption(inputLabel)
        styleCaption(outputLabel)
        historyLabel.font = .systemFont(ofSize: 12, weight: .medium)
        historyLabel.textColor = Theme.muted

        [titleLabel, subtitleLabel, sourceButton, targetButton, swapButton, clearButton,
         lookupSplit, seal].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview($0)
        }

        NSLayoutConstraint.activate([
            seal.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 22),
            seal.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            seal.widthAnchor.constraint(equalToConstant: 38),
            seal.heightAnchor.constraint(equalToConstant: 38),

            titleLabel.leadingAnchor.constraint(equalTo: seal.trailingAnchor, constant: 10),
            titleLabel.topAnchor.constraint(equalTo: seal.topAnchor, constant: -2),
            subtitleLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 1),

            sourceButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 22),
            sourceButton.topAnchor.constraint(equalTo: seal.bottomAnchor, constant: 18),
            sourceButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 96),
            sourceButton.widthAnchor.constraint(lessThanOrEqualToConstant: 120),

            swapButton.leadingAnchor.constraint(equalTo: sourceButton.trailingAnchor, constant: 8),
            swapButton.centerYAnchor.constraint(equalTo: sourceButton.centerYAnchor),
            swapButton.widthAnchor.constraint(equalToConstant: 36),

            targetButton.leadingAnchor.constraint(equalTo: swapButton.trailingAnchor, constant: 8),
            targetButton.centerYAnchor.constraint(equalTo: sourceButton.centerYAnchor),
            targetButton.widthAnchor.constraint(equalTo: sourceButton.widthAnchor),
            targetButton.trailingAnchor.constraint(lessThanOrEqualTo: clearButton.leadingAnchor, constant: -10),

            clearButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -22),
            clearButton.centerYAnchor.constraint(equalTo: sourceButton.centerYAnchor),
            clearButton.leadingAnchor.constraint(greaterThanOrEqualTo: targetButton.trailingAnchor, constant: 10),

            lookupSplit.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 22),
            lookupSplit.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -22),
            lookupSplit.topAnchor.constraint(equalTo: sourceButton.bottomAnchor, constant: 16),
            lookupSplit.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -16),
        ])
    }

    private func styleCaption(_ label: NSTextField) {
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.textColor = Theme.muted
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    }

    private func configureLookupSplit() {
        lookupSplit.isVertical = false
        lookupSplit.dividerStyle = .paneSplitter
        lookupSplit.delegate = self
        lookupSplit.arrangesAllSubviews = true

        layoutPane(inputPane, label: inputLabel, scroll: inputScroll)
        layoutPane(outputPane, label: outputLabel, leadingControl: spinner, scroll: outputScroll)
        layoutPane(historyPane, label: historyLabel, scroll: historyScroll)

        lookupSplit.addArrangedSubview(inputPane)
        lookupSplit.addArrangedSubview(outputPane)
        lookupSplit.addArrangedSubview(historyPane)
        lookupSplit.setHoldingPriority(.init(260), forSubviewAt: 0)
        lookupSplit.setHoldingPriority(.init(1), forSubviewAt: 1)
        lookupSplit.setHoldingPriority(.init(255), forSubviewAt: 2)
    }

    private func layoutPane(
        _ pane: NSView,
        label: NSTextField,
        leadingControl: NSView? = nil,
        trailingControl: NSView? = nil,
        scroll: NSScrollView
    ) {
        pane.wantsLayer = true
        var pieces: [NSView] = [label, scroll]
        if let leadingControl { pieces.append(leadingControl) }
        if let trailingControl { pieces.append(trailingControl) }
        for item in pieces {
            item.translatesAutoresizingMaskIntoConstraints = false
            if item.superview != pane {
                item.removeFromSuperview()
                pane.addSubview(item)
            }
        }

        var constraints: [NSLayoutConstraint] = [
            label.leadingAnchor.constraint(equalTo: pane.leadingAnchor, constant: 2),
            label.topAnchor.constraint(equalTo: pane.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: pane.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: pane.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: label.bottomAnchor, constant: 6),
            scroll.bottomAnchor.constraint(equalTo: pane.bottomAnchor),
        ]
        if let trailingControl {
            constraints.append(contentsOf: [
                trailingControl.trailingAnchor.constraint(equalTo: pane.trailingAnchor, constant: -2),
                trailingControl.centerYAnchor.constraint(equalTo: label.centerYAnchor),
                trailingControl.leadingAnchor.constraint(greaterThanOrEqualTo: (leadingControl ?? label).trailingAnchor, constant: 8),
            ])
        }
        if let leadingControl {
            constraints.append(contentsOf: [
                leadingControl.leadingAnchor.constraint(equalTo: label.trailingAnchor, constant: 8),
                leadingControl.centerYAnchor.constraint(equalTo: label.centerYAnchor),
            ])
        }
        NSLayoutConstraint.activate(constraints)
    }

    private func applyDefaultSplitIfNeeded() {
        guard !didSetSplitPosition else { return }
        let height = lookupSplit.bounds.height
        guard height > 280 else { return }
        didSetSplitPosition = true

        let autosaveKey = "NSSplitView Subview Frames \(splitAutosaveName)"
        if UserDefaults.standard.object(forKey: autosaveKey) != nil {
            lookupSplit.autosaveName = splitAutosaveName
            return
        }

        let divider = lookupSplit.dividerThickness
        let entry = entryDefaultHeight
        var recent = recentDefaultHeight
        let needed = entry + recent + translationMinHeight + divider * 2
        if needed > height {
            recent = max(recentMinHeight, height - entry - translationMinHeight - divider * 2)
        }
        lookupSplit.setPosition(entry, ofDividerAt: 0)
        lookupSplit.setPosition(height - recent, ofDividerAt: 1)
        lookupSplit.autosaveName = splitAutosaveName
    }

    private var entryDefaultHeight: CGFloat {
        let lineHeight = ceil(NSFont.systemFont(ofSize: 16).boundingRectForFont.height)
        let textBox = 10 + lineHeight * 2 + 10
        return 18 + 6 + textBox
    }

    private var recentDefaultHeight: CGFloat {
        let header = historyTable.headerView?.bounds.height ?? 28
        let row = historyTable.rowHeight
        let spacing = historyTable.intercellSpacing.height
        return 18 + 6 + header + row * 5 + spacing * 4 + 6
    }

    func splitView(_ splitView: NSSplitView, constrainMinCoordinate proposedMinimumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
        let thickness = splitView.dividerThickness
        if dividerIndex == 0 { return entryMinHeight }
        return entryMinHeight + translationMinHeight + thickness
    }

    func splitView(_ splitView: NSSplitView, constrainMaxCoordinate proposedMaximumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
        let thickness = splitView.dividerThickness
        if dividerIndex == 0 {
            return splitView.bounds.height - translationMinHeight - recentMinHeight - thickness
        }
        return splitView.bounds.height - recentMinHeight
    }

    func splitView(_ splitView: NSSplitView, canCollapse subview: NSView) -> Bool {
        false
    }

    func splitView(_ splitView: NSSplitView, shouldAdjustSizeOfSubview view: NSView) -> Bool {
        view === outputPane
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
        if editable {
            textView.isContinuousSpellCheckingEnabled = true
            textView.isAutomaticSpellingCorrectionEnabled = false
            textView.isGrammarCheckingEnabled = false
            textView.enabledTextCheckingTypes = NSTextCheckingResult.CheckingType.spelling.rawValue
        } else {
            textView.isContinuousSpellCheckingEnabled = false
            textView.isAutomaticSpellingCorrectionEnabled = false
        }
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
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.autoresizingMask = [.width]
    }

    private func configureHistoryTable() {
        let queryColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("query"))
        queryColumn.title = "Query"
        queryColumn.minWidth = 80
        queryColumn.width = 140

        let translationColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("translation"))
        translationColumn.title = "Translation"
        translationColumn.minWidth = 120
        translationColumn.width = 220

        historyTable.addTableColumn(queryColumn)
        historyTable.addTableColumn(translationColumn)
        historyTable.headerView = NSTableHeaderView()
        historyTable.dataSource = self
        historyTable.delegate = self
        historyTable.rowHeight = 28
        historyTable.backgroundColor = Theme.panel
        historyTable.usesAlternatingRowBackgroundColors = true
        historyTable.allowsEmptySelection = true
        historyTable.allowsMultipleSelection = false
        historyTable.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        historyTable.autoresizingMask = [.width]
        queryColumn.resizingMask = .userResizingMask
        translationColumn.resizingMask = [.autoresizingMask, .userResizingMask]
        historyTable.target = self
        historyTable.action = #selector(historyRowClicked)
        historyTable.doubleAction = #selector(historyRowClicked)

        historyScroll.hasVerticalScroller = true
        historyScroll.autohidesScrollers = false
        historyScroll.hasHorizontalScroller = false
        historyScroll.scrollerInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 2)
        historyScroll.borderType = .lineBorder
        historyScroll.backgroundColor = Theme.panel
        historyScroll.drawsBackground = true
        historyScroll.documentView = historyTable
        historyScroll.wantsLayer = true
        historyScroll.layer?.cornerRadius = 8
        historyScroll.layer?.borderWidth = 1
        historyScroll.layer?.borderColor = Theme.line.cgColor
        refreshHistoryLabel()
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        history.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard history.indices.contains(row) else { return nil }
        let identifier = tableColumn?.identifier ?? NSUserInterfaceItemIdentifier("query")
        let item = history[row]
        if identifier.rawValue == "translation" {
            let cell = tableView.makeView(withIdentifier: identifier, owner: self) as? HistoryTranslationCell
                ?? HistoryTranslationCell(identifier: identifier, target: self, action: #selector(deleteHistory(_:)))
            cell.textField?.stringValue = collapsed(item.translation)
            cell.deleteButton.tag = row
            return cell
        }

        let cell = tableView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView
            ?? makeHistoryCell(identifier: identifier)
        cell.textField?.stringValue = collapsed(item.query)
        return cell
    }

    private func makeHistoryCell(identifier: NSUserInterfaceItemIdentifier) -> NSTableCellView {
        let cell = NSTableCellView()
        cell.identifier = identifier
        let field = historyTextField()
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
        if ignoreNextHistoryClick {
            ignoreNextHistoryClick = false
            return
        }
        let row = historyTable.clickedRow
        guard history.indices.contains(row) else { return }
        inputView.string = history[row].query
        inputView.checkTextInDocument(nil)
        updateDirectionLabel()
        startLookup()
    }

    @objc private func deleteHistory(_ sender: NSButton) {
        let row = sender.tag
        guard history.indices.contains(row) else { return }
        ignoreNextHistoryClick = true
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
        refreshHistoryLabel()
        WidgetCenter.shared.reloadAllTimelines()
    }

    private func refreshHistoryLabel() {
        historyLabel.stringValue = history.isEmpty ? "Recent" : "Recent · \(history.count)"
    }

    func textDidChange(_ notification: Notification) {
        guard notification.object as? NSTextView === inputView else { return }
        updateDirectionLabel()
        debounceWork?.cancel()
        translateGeneration += 1
        spinner.stopAnimation(nil)
        let work = DispatchWorkItem { [weak self] in
            self?.startLookup()
        }
        debounceWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: work)
    }

    @objc private func sourceChanged() {
        if sourceButton.indexOfSelectedItem == 0 {
            sourceIsAuto = true
        } else {
            sourceIsAuto = false
            source = Language.allCases[sourceButton.indexOfSelectedItem - 1]
            if source == target {
                target = source == .zh ? .en : .zh
                targetButton.selectItem(withTitle: target.label)
            }
        }
        updateDirectionLabel()
        startLookup()
    }

    @objc private func targetChanged() {
        target = Language.allCases[targetButton.indexOfSelectedItem]
        if !sourceIsAuto, source == target {
            source = target == .zh ? .en : .zh
            sourceButton.selectItem(withTitle: source.label)
        }
        updateDirectionLabel()
        startLookup()
    }

    @objc private func swapLanguages() {
        if sourceIsAuto {
            target = target == .zh ? .en : .zh
            targetButton.selectItem(withTitle: target.label)
        } else {
            swap(&source, &target)
            sourceButton.selectItem(withTitle: source.label)
            targetButton.selectItem(withTitle: target.label)
        }
        updateDirectionLabel()
        startLookup()
    }

    @objc private func clearAll() {
        debounceWork?.cancel()
        translateGeneration += 1
        inputView.string = ""
        inputView.checkTextInDocument(nil)
        spinner.stopAnimation(nil)
        showPlaceholder()
        updateDirectionLabel()
    }

    private func currentPair(for text: String? = nil) -> (Language, Language) {
        let sample = (text ?? inputView.string).trimmingCharacters(in: .whitespacesAndNewlines)
        if sourceIsAuto {
            if sample.isEmpty {
                return TranslatorService.resolvedPair(source: .en, target: target)
            }
            return Language.pair(detecting: sample, preferredTarget: target)
        }
        return TranslatorService.resolvedPair(source: source, target: target)
    }

    private func updateDirectionLabel() {
        let pair = currentPair()
        if sourceIsAuto {
            let sample = inputView.string.trimmingCharacters(in: .whitespacesAndNewlines)
            subtitleLabel.stringValue = sample.isEmpty
                ? "Auto · English or Chinese"
                : "Auto · \(pair.0.label) → \(pair.1.label)"
        } else {
            subtitleLabel.stringValue = "\(pair.0.label) → \(pair.1.label)"
        }
    }

    private func showPlaceholder() {
        outputView.textStorage?.setAttributedString(EntryRenderer.placeholder())
    }

    private func startLookup() {
        let text = inputView.string
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            showPlaceholder()
            return
        }

        translateGeneration += 1
        let generation = translateGeneration
        let pair = currentPair(for: text)
        spinner.startAnimation(nil)

        Task {
            do {
                let entry = try await DictionaryService.lookup(text, from: pair.0, to: pair.1)
                await MainActor.run {
                    guard generation == self.translateGeneration else { return }
                    self.outputView.textStorage?.setAttributedString(EntryRenderer.render(entry))
                    self.recordHistory(query: entry.query, translation: entry.historyLine)
                    self.spinner.stopAnimation(nil)
                }
            } catch {
                await MainActor.run {
                    guard generation == self.translateGeneration else { return }
                    let message = (error as? LocalizedError)?.errorDescription ?? TranslatorError.failed.errorDescription ?? "Lookup failed."
                    self.outputView.textStorage?.setAttributedString(EntryRenderer.error(message))
                    self.spinner.stopAnimation(nil)
                }
            }
        }
    }
}

final class PaneSplitView: NSSplitView {
    override var isFlipped: Bool { true }
    override var dividerColor: NSColor { Theme.line }
    override var dividerThickness: CGFloat { 10 }

    override func drawDivider(in rect: NSRect) {
        Theme.paper.setFill()
        rect.fill()

        let grip: NSRect
        if isVertical {
            grip = NSRect(x: rect.midX - 1, y: rect.midY - 16, width: 2, height: 32)
        } else {
            grip = NSRect(x: rect.midX - 16, y: rect.midY - 1, width: 32, height: 2)
        }
        Theme.line.setFill()
        NSBezierPath(roundedRect: grip, xRadius: 1, yRadius: 1).fill()
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

private func historyTextField() -> NSTextField {
    let field = NSTextField(labelWithString: "")
    field.font = .systemFont(ofSize: 12)
    field.textColor = Theme.ink
    field.lineBreakMode = .byTruncatingTail
    field.maximumNumberOfLines = 1
    field.drawsBackground = false
    field.isBordered = false
    field.cell?.usesSingleLineMode = true
    field.cell?.lineBreakMode = .byTruncatingTail
    field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    field.translatesAutoresizingMaskIntoConstraints = false
    return field
}

final class HistoryTranslationCell: NSTableCellView {
    let deleteButton = NSButton()

    init(identifier: NSUserInterfaceItemIdentifier, target: AnyObject, action: Selector) {
        super.init(frame: .zero)
        self.identifier = identifier

        let field = historyTextField()
        addSubview(field)
        textField = field

        deleteButton.isBordered = false
        deleteButton.bezelStyle = .regularSquare
        deleteButton.imagePosition = .imageOnly
        deleteButton.focusRingType = .none
        let symbol = NSImage.SymbolConfiguration(pointSize: 11, weight: .medium)
        deleteButton.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Delete")?
            .withSymbolConfiguration(symbol)
        deleteButton.contentTintColor = Theme.seal
        deleteButton.toolTip = "Delete this record"
        deleteButton.target = target
        deleteButton.action = action
        deleteButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(deleteButton)

        NSLayoutConstraint.activate([
            deleteButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            deleteButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            deleteButton.widthAnchor.constraint(equalToConstant: 18),
            deleteButton.heightAnchor.constraint(equalToConstant: 18),

            field.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            field.trailingAnchor.constraint(equalTo: deleteButton.leadingAnchor, constant: -4),
            field.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) {
        nil
    }
}
