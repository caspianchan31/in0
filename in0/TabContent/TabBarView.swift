import AppKit

/// One quick-action button's worth of state. The host (TabBridge) maps a
/// `QuickActionsStore.displayList` into this lightweight shape; the bar
/// itself is intentionally ignorant of the store so its rendering doesn't
/// re-observe on every store mutation.
struct QuickActionDescriptor {
    let id: QuickActionId
    let title: String
    let tooltip: String
    let symbolName: String?     // SF Symbol — nil when the row should fall back to letter
    let assetName: String?      // asset catalog image — nil unless action ships one
    let letter: Character?      // fallback chip when symbolName is nil
}

/// Horizontal tab strip drawn in AppKit. Each tab cell is a sub-NSView with
/// a title, a close button, and click-to-select. Re-renders on `apply(...)`.
@MainActor
final class TabBarView: NSView {
    var theme: AppTheme {
        didSet { needsDisplay = true; refreshCells() }
    }

    private var tabs: [TerminalTab] = []
    private var selectedTabId: UUID?

    var onSelect: ((UUID) -> Void)?
    var onClose: ((UUID) -> Void)?
    var onAdd: (() -> Void)?
    var onSplitVertical: (() -> Void)?
    var onSplitHorizontal: (() -> Void)?
    var onRename: ((UUID, String) -> Void)?
    var onReorder: ((_ from: Int, _ to: Int) -> Void)?
    var onQuickAction: ((QuickActionId) -> Void)?

    private var quickActionDescriptors: [QuickActionDescriptor] = []

    private var dropIndicatorX: CGFloat? { didSet { needsDisplay = true } }

    private let stackView = NSStackView()
    private let addButton = NSButton()
    private let splitVerticalButton = NSButton()
    private let splitHorizontalButton = NSButton()
    private let controlStack = NSStackView()
    private let quickActionStack = NSStackView()
    private var quickActionButtons: [NSButton] = []
    init(theme: AppTheme) {
        self.theme = theme
        super.init(frame: .zero)
        wantsLayer = true
        setup()
    }

    required init?(coder: NSCoder) { fatalError("not supported") }

    private func setup() {
        stackView.orientation = .horizontal
        stackView.alignment = .centerY
        stackView.spacing = 0
        stackView.edgeInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
        stackView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stackView)

        configureIconButton(addButton, symbol: "plus", description: "New tab", action: #selector(addClicked))
        configureIconButton(splitVerticalButton, symbol: "rectangle.split.2x1", description: "Split right", action: #selector(splitVerticalClicked))
        configureIconButton(splitHorizontalButton, symbol: "rectangle.split.1x2", description: "Split down", action: #selector(splitHorizontalClicked))

        controlStack.orientation = .horizontal
        controlStack.alignment = .centerY
        controlStack.spacing = 4
        controlStack.translatesAutoresizingMaskIntoConstraints = false
        controlStack.addArrangedSubview(splitVerticalButton)
        controlStack.addArrangedSubview(splitHorizontalButton)
        controlStack.addArrangedSubview(addButton)
        addSubview(controlStack)

        quickActionStack.orientation = .horizontal
        quickActionStack.alignment = .centerY
        quickActionStack.spacing = 6
        quickActionStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(quickActionStack)

        registerForDraggedTypes([NSPasteboard.PasteboardType.in0Tab])

        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            stackView.topAnchor.constraint(equalTo: topAnchor),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor),
            stackView.trailingAnchor.constraint(lessThanOrEqualTo: quickActionStack.leadingAnchor, constant: -12),
            quickActionStack.trailingAnchor.constraint(equalTo: controlStack.leadingAnchor, constant: -12),
            quickActionStack.centerYAnchor.constraint(equalTo: centerYAnchor),
            controlStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            controlStack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    private func configureIconButton(
        _ button: NSButton,
        symbol: String,
        description: String,
        action: Selector
    ) {
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: description)
        button.imagePosition = .imageOnly
        button.bezelStyle = .accessoryBarAction
        button.isBordered = false
        button.contentTintColor = theme.foregroundNS
        button.target = self
        button.action = action
        button.toolTip = description
        button.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: 22),
            button.heightAnchor.constraint(equalToConstant: 22),
        ])
    }

    func apply(tabs: [TerminalTab], selected: UUID?) {
        self.tabs = tabs
        self.selectedTabId = selected
        rebuildCells()
    }

    /// Dynamic quick-action cluster. Called whenever the store's display
    /// list changes (enable / disable / reorder / rename). We rebuild the
    /// button row from scratch — the row is small and rebuilding sidesteps
    /// any sync issues between AppKit state and the store.
    func applyQuickActions(_ descriptors: [QuickActionDescriptor]) {
        self.quickActionDescriptors = descriptors
        for view in quickActionStack.arrangedSubviews {
            quickActionStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        quickActionButtons.removeAll(keepingCapacity: true)
        for (idx, desc) in descriptors.enumerated() {
            let button = NSButton()
            if let symbol = desc.symbolName,
               let image = NSImage(systemSymbolName: symbol, accessibilityDescription: desc.title) {
                button.image = image
                button.imagePosition = .imageLeading
                button.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 10, weight: .bold)
            } else if let asset = desc.assetName,
                      let image = NSImage(named: asset) {
                image.isTemplate = true
                button.image = image
                button.imagePosition = .imageLeading
            }
            button.title = quickActionTitle(for: desc)
            button.bezelStyle = .accessoryBarAction
            button.isBordered = false
            button.font = .systemFont(ofSize: 10, weight: .semibold)
            button.contentTintColor = theme.foregroundNS
            button.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            button.lineBreakMode = .byTruncatingTail
            button.target = self
            button.action = #selector(quickActionClicked(_:))
            button.tag = idx
            button.toolTip = desc.tooltip
            button.translatesAutoresizingMaskIntoConstraints = false
            button.widthAnchor.constraint(lessThanOrEqualToConstant: 116).isActive = true
            quickActionButtons.append(button)
            quickActionStack.addArrangedSubview(button)
        }
        refreshCells()
    }

    private func quickActionTitle(for desc: QuickActionDescriptor) -> String {
        guard desc.symbolName == nil, desc.assetName == nil, let letter = desc.letter else {
            return desc.title
        }
        return "\(letter) \(desc.title)"
    }

    private func rebuildCells() {
        for view in stackView.arrangedSubviews {
            stackView.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        for tab in tabs {
            let cell = TabCellView(
                tab: tab,
                selected: tab.id == selectedTabId,
                theme: theme,
                onSelect: { [weak self] id in self?.onSelect?(id) },
                onClose: { [weak self] id in self?.onClose?(id) },
                onRename: { [weak self] id, name in self?.onRename?(id, name) }
            )
            stackView.addArrangedSubview(cell)
        }
    }

    private func refreshCells() {
        addButton.contentTintColor = theme.foregroundNS
        splitVerticalButton.contentTintColor = theme.foregroundNS
        splitHorizontalButton.contentTintColor = theme.foregroundNS
        for button in quickActionButtons {
            button.contentTintColor = theme.foregroundNS
            let attr = NSAttributedString(string: button.title, attributes: [
                .foregroundColor: theme.foregroundNS,
                .font: NSFont.systemFont(ofSize: 10, weight: .semibold),
            ])
            button.attributedTitle = attr
        }
        for case let cell as TabCellView in stackView.arrangedSubviews {
            cell.theme = theme
        }
    }

    @objc private func quickActionClicked(_ sender: NSButton) {
        guard sender.tag >= 0, sender.tag < quickActionDescriptors.count else { return }
        onQuickAction?(quickActionDescriptors[sender.tag].id)
    }

    @objc private func addClicked() {
        onAdd?()
    }

    @objc private func splitVerticalClicked() {
        onSplitVertical?()
    }

    @objc private func splitHorizontalClicked() {
        onSplitHorizontal?()
    }

    fileprivate func handleCellDragStart(_ cell: TabCellView, event: NSEvent) {
        let item = NSPasteboardItem()
        item.setString(cell.tab.id.uuidString, forType: NSPasteboard.PasteboardType.in0Tab)
        let dragItem = NSDraggingItem(pasteboardWriter: item)
        if let raw = cell.snapshot() {
            // Wrap the raw cell snapshot in the layered shadow so the
            // ghost looks lifted off the tab bar rather than slapped onto
            // the desktop. The frame includes the halo padding offset, so
            // the cursor still anchors to the original tab hit point.
            let composed = DraggedSnapshotShadow.compose(
                content: raw,
                contentSize: cell.frame.size,
                cornerRadius: DT.Radius.row
            )
            var framed = composed.frame
            framed.origin.x += cell.frame.origin.x
            framed.origin.y += cell.frame.origin.y
            dragItem.setDraggingFrame(framed, contents: composed.image)
        } else {
            dragItem.setDraggingFrame(cell.frame, contents: cell.snapshot())
        }
        beginDraggingSession(with: [dragItem], event: event, source: self)
    }

    private func tabIdFromDragInfo(_ info: NSDraggingInfo) -> UUID? {
        guard let raw = info.draggingPasteboard.string(forType: NSPasteboard.PasteboardType.in0Tab) else { return nil }
        return UUID(uuidString: raw)
    }

    private func dropIndex(for info: NSDraggingInfo) -> Int? {
        let cells = stackView.arrangedSubviews.compactMap { $0 as? TabCellView }
        guard !cells.isEmpty else { return 0 }
        let pointInBar = convert(info.draggingLocation, from: nil)
        let pointInStack = stackView.convert(pointInBar, from: self)
        for (idx, cell) in cells.enumerated() {
            let midX = cell.frame.midX
            if pointInStack.x < midX { return idx }
        }
        return cells.count
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        if tabIdFromDragInfo(sender) == nil { return [] }
        updateDropIndicator(sender)
        return .move
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        if tabIdFromDragInfo(sender) == nil { return [] }
        updateDropIndicator(sender)
        return .move
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        dropIndicatorX = nil
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        defer { dropIndicatorX = nil }
        guard let tabId = tabIdFromDragInfo(sender),
              let from = tabs.firstIndex(where: { $0.id == tabId }),
              let to = dropIndex(for: sender) else { return false }
        if to == from || to == from + 1 { return false }
        onReorder?(from, to)
        return true
    }

    private func updateDropIndicator(_ info: NSDraggingInfo) {
        guard let idx = dropIndex(for: info) else { return }
        let cells = stackView.arrangedSubviews.compactMap { $0 as? TabCellView }
        let xInStack: CGFloat
        if idx >= cells.count, let last = cells.last {
            xInStack = last.frame.maxX
        } else {
            xInStack = cells[idx].frame.minX
        }
        let pointInBar = stackView.convert(NSPoint(x: xInStack, y: 0), to: self)
        dropIndicatorX = pointInBar.x
    }

    override func draw(_ dirtyRect: NSRect) {
        // call the original drawing
        theme.sidebarNS.setFill()
        bounds.fill()
        let leadingRule = NSRect(x: 0, y: 0, width: 1, height: bounds.height)
        theme.borderStrongNS.setFill()
        leadingRule.fill()
        let line = NSRect(x: 0, y: 0, width: bounds.width, height: 1)
        theme.borderStrongNS.setFill()
        line.fill()
        if let x = dropIndicatorX {
            theme.foregroundNS.setFill()
            NSRect(x: x - 1, y: 6, width: 2, height: bounds.height - 12).fill()
        }
    }
}

extension TabBarView: NSDraggingSource {
    nonisolated func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        return .move
    }
}

private final class TabCellView: NSView, NSTextFieldDelegate {
    let tab: TerminalTab
    var selected: Bool { didSet { needsDisplay = true; updateLabelColor(); updateCloseTint() } }
    var theme: AppTheme {
        didSet {
            needsDisplay = true
            updateLabelColor()
            updateCloseTint()
        }
    }

    private let onSelect: (UUID) -> Void
    private let onClose: (UUID) -> Void
    private let onRename: (UUID, String) -> Void
    private let iconView = NSImageView()
    private let label = NSTextField(labelWithString: "")
    private let editField = NSTextField()
    private let closeButton = NSButton()
    private var isEditing = false

    private var trackingArea: NSTrackingArea?
    private var hovering = false { didSet { needsDisplay = true } }

    init(
        tab: TerminalTab,
        selected: Bool,
        theme: AppTheme,
        onSelect: @escaping (UUID) -> Void,
        onClose: @escaping (UUID) -> Void,
        onRename: @escaping (UUID, String) -> Void
    ) {
        self.tab = tab
        self.selected = selected
        self.theme = theme
        self.onSelect = onSelect
        self.onClose = onClose
        self.onRename = onRename
        super.init(frame: .zero)
        wantsLayer = true
        setup()
    }
    required init?(coder: NSCoder) { fatalError("not supported") }

    private func setup() {
        iconView.image = NSImage(systemSymbolName: "terminal", accessibilityDescription: "Terminal tab")
        iconView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 10, weight: .bold)
        iconView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(iconView)

        label.stringValue = tab.title.uppercased()
        label.font = .systemFont(ofSize: 10, weight: .bold)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.lineBreakMode = .byTruncatingTail
        addSubview(label)

        editField.stringValue = tab.title
        editField.font = .systemFont(ofSize: 10, weight: .bold)
        editField.isBezeled = false
        editField.isBordered = false
        editField.drawsBackground = false
        editField.focusRingType = .none
        editField.translatesAutoresizingMaskIntoConstraints = false
        editField.isHidden = true
        editField.delegate = self
        editField.target = self
        editField.action = #selector(commitEdit)
        addSubview(editField)

        closeButton.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Close tab")
        closeButton.imagePosition = .imageOnly
        closeButton.bezelStyle = .accessoryBarAction
        closeButton.isBordered = false
        closeButton.target = self
        closeButton.action = #selector(closeClicked)
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(closeButton)

        updateLabelColor()
        updateCloseTint()

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: DT.Layout.tabBarHeight),
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 14),
            iconView.heightAnchor.constraint(equalToConstant: 14),
            label.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 7),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            editField.leadingAnchor.constraint(equalTo: label.leadingAnchor),
            editField.centerYAnchor.constraint(equalTo: centerYAnchor),
            editField.trailingAnchor.constraint(equalTo: closeButton.leadingAnchor, constant: -8),
            closeButton.leadingAnchor.constraint(equalTo: label.trailingAnchor, constant: 8),
            closeButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            closeButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            closeButton.widthAnchor.constraint(equalToConstant: 14),
            closeButton.heightAnchor.constraint(equalToConstant: 14),
        ])
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let ta = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(ta)
        trackingArea = ta
    }

    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }

    override var intrinsicContentSize: NSSize {
        let w = label.intrinsicContentSize.width + 10 + 14 + 7 + 8 + 14 + 8
        return NSSize(width: min(max(w, 92), 168), height: DT.Layout.tabBarHeight)
    }

    override func draw(_ dirtyRect: NSRect) {
        if selected {
            theme.selectionNS.withAlphaComponent(0.72).setFill()
            NSBezierPath(roundedRect: bounds.insetBy(dx: 2, dy: 4), xRadius: DT.Radius.row, yRadius: DT.Radius.row).fill()
        } else if hovering {
            theme.borderNS.withAlphaComponent(0.45).setFill()
            NSBezierPath(roundedRect: bounds.insetBy(dx: 2, dy: 4), xRadius: DT.Radius.row, yRadius: DT.Radius.row).fill()
        }
    }

    private func updateLabelColor() {
        label.font = .systemFont(ofSize: 10, weight: .bold)
        label.textColor = selected ? theme.foregroundNS : theme.textSecondaryNS
        iconView.contentTintColor = selected ? theme.foregroundNS : theme.textSecondaryNS
    }

    private func updateCloseTint() {
        closeButton.contentTintColor = selected ? theme.foregroundNS : theme.textSecondaryNS.withAlphaComponent(0.72)
    }

    private var mouseDownAt: NSPoint?

    override func mouseDown(with event: NSEvent) {
        if event.clickCount >= 2 {
            beginEditing()
            return
        }
        mouseDownAt = event.locationInWindow
        onSelect(tab.id)
    }

    override func mouseDragged(with event: NSEvent) {
        guard !isEditing, let start = mouseDownAt else { return }
        let here = event.locationInWindow
        let dist = hypot(here.x - start.x, here.y - start.y)
        guard dist > 5 else { return }
        mouseDownAt = nil
        if let bar = superview?.superview as? TabBarView {
            bar.handleCellDragStart(self, event: event)
        }
    }

    override func mouseUp(with event: NSEvent) {
        mouseDownAt = nil
    }

    func snapshot() -> NSImage? {
        guard let rep = bitmapImageRepForCachingDisplay(in: bounds) else { return nil }
        cacheDisplay(in: bounds, to: rep)
        let img = NSImage(size: bounds.size)
        img.addRepresentation(rep)
        return img
    }

    @objc private func closeClicked() {
        onClose(tab.id)
    }

    private func beginEditing() {
        guard !isEditing else { return }
        isEditing = true
        editField.stringValue = tab.title
        editField.textColor = theme.foregroundNS
        label.isHidden = true
        editField.isHidden = false
        window?.makeFirstResponder(editField)
        editField.currentEditor()?.selectAll(nil)
    }

    @objc private func commitEdit() {
        finishEditing(commit: true)
    }

    private func finishEditing(commit: Bool) {
        guard isEditing else { return }
        isEditing = false
        let raw = editField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        editField.isHidden = true
        label.isHidden = false
        if commit && !raw.isEmpty && raw != tab.title {
            label.stringValue = raw.uppercased()
            onRename(tab.id, raw)
        }
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            finishEditing(commit: false)
            return true
        }
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            finishEditing(commit: true)
            return true
        }
        return false
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        if isEditing { finishEditing(commit: true) }
    }
}
