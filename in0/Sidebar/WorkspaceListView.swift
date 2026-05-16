import AppKit

// MARK: - FlippedRowsContainer

/// Document-view container with a flipped coordinate space: row 0 lives at
/// y=0 in the top, indexes grow downward. AppKit's default bottom-left
/// origin means every row layout would otherwise be `(height - i*rowH)`
/// arithmetic; flipping once here cleans up every site below.
private final class FlippedRowsContainer: NSView {
    override var isFlipped: Bool { true }
}

// MARK: - WorkspaceListView

/// Sidebar workspace list, AppKit-backed (parallels `TabBarView`).
/// Drag-reorder, hover, inline rename, and the right-click menu all live
/// here; the SwiftUI `SidebarView` is just a shell that adds the header
/// and footer chrome around it.
final class WorkspaceListView: NSView {
    var onSelect: ((UUID) -> Void)?
    var onRename: ((UUID, String) -> Void)?
    var onReorder: ((Int, Int) -> Void)?       // (fromIndex, insertionIndex 0…count)
    var onRequestDelete: ((UUID) -> Void)?
    /// Row-level "edit default command" bubbles up here with the current
    /// value; the SwiftUI shell shows the alert + writes back through
    /// `WorkspaceStore.updateDefaultCommand`.
    var onRequestEditCommand: ((UUID, String) -> Void)?

    private let scrollView = NSScrollView()
    private let rowsContainer = FlippedRowsContainer()
    private var theme: AppTheme = .darkDefault
    /// Mirrors ghostty's `background-opacity`. Applied to selected /
    /// hovered row fills so they don't paint over the (now translucent)
    /// sidebar plate.
    private var backgroundOpacity: CGFloat = 1.0
    private var workspaces: [Workspace] = []
    private var selectedId: UUID?
    private var metadataMap: [UUID: WorkspaceMetadataSnapshot] = [:]
    private var statusMap: [UUID: TerminalStatus] = [:]
    /// Feature gate for the per-row status icon. When false the icon is
    /// hidden AND its layout slot collapses, so the title uses the full
    /// width.
    private var showStatusIndicators: Bool = false

    // Drag preview state
    fileprivate var draggingId: UUID?
    fileprivate var previewInsertionIndex: Int?

    static let baseRowHeight: CGFloat = 44
    static let rowSpacing: CGFloat = 3
    static let outerHorizontalInset: CGFloat = DT.Space.sm

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        scrollView.hasHorizontalScroller = false
        scrollView.hasVerticalScroller = false
        scrollView.drawsBackground = false
        scrollView.documentView = rowsContainer
        scrollView.autoresizingMask = []
        addSubview(scrollView)
        registerForDraggedTypes([.in0Workspace])

        // While scrolling, AppKit doesn't reliably re-pair mouseEntered /
        // mouseExited if the cursor sits still and rows scroll past it.
        // Recompute hover state from the actual cursor position on every
        // scroll so we don't leave stale hover backgrounds behind.
        scrollView.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(contentViewBoundsDidChange),
            name: NSView.boundsDidChangeNotification,
            object: scrollView.contentView
        )
    }
    required init?(coder: NSCoder) { fatalError("not supported") }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func contentViewBoundsDidChange() {
        syncHoverFromMouseLocation()
    }

    private func syncHoverFromMouseLocation() {
        let rows = rowsContainer.subviews.compactMap { $0 as? WorkspaceRowItemView }
        guard let window else {
            for row in rows where row.isHovered {
                row.isHovered = false
                row.updateStyle()
            }
            return
        }
        let mouseInWindow = window.mouseLocationOutsideOfEventStream
        for row in rows {
            let pInRow = row.convert(mouseInWindow, from: nil)
            let shouldHover = row.bounds.contains(pInRow)
            if row.isHovered != shouldHover {
                row.isHovered = shouldHover
                row.updateStyle()
            }
        }
    }

    override func layout() {
        super.layout()
        scrollView.frame = bounds
        layoutRows(animated: false)
    }

    func update(workspaces: [Workspace],
                selectedId: UUID?,
                metadata: [UUID: WorkspaceMetadataSnapshot],
                statuses: [UUID: TerminalStatus] = [:],
                theme: AppTheme,
                backgroundOpacity: CGFloat = 1.0,
                showStatusIndicators: Bool = false) {
        self.workspaces = workspaces
        self.selectedId = selectedId
        self.metadataMap = metadata
        self.statusMap = statuses
        self.theme = theme
        self.backgroundOpacity = backgroundOpacity
        self.showStatusIndicators = showStatusIndicators
        rebuildRows()
        applyTheme(theme, backgroundOpacity: backgroundOpacity)
    }

    private func workspaceStatus(_ ws: Workspace) -> TerminalStatus {
        let ids = ws.tabs.flatMap { $0.layout.allTerminalIds() }
        return TerminalStatus.aggregate(ids.map { statusMap[$0] ?? .neverRan })
    }

    func applyTheme(_ theme: AppTheme, backgroundOpacity: CGFloat = 1.0) {
        self.theme = theme
        self.backgroundOpacity = backgroundOpacity
        rowsContainer.subviews
            .compactMap { $0 as? WorkspaceRowItemView }
            .forEach { $0.applyTheme(theme, backgroundOpacity: backgroundOpacity) }
        needsDisplay = true
    }

    /// id-diff rebuild: full teardown only when the workspace sequence
    /// changes. Otherwise refresh each row in place so rename's first
    /// responder + the in-flight drag session don't get rug-pulled.
    private func rebuildRows() {
        let existing = rowsContainer.subviews.compactMap { $0 as? WorkspaceRowItemView }
        let existingIds = existing.map(\.workspaceId)
        let targetIds = workspaces.map(\.id)

        if existingIds == targetIds {
            for item in existing {
                guard let ws = workspaces.first(where: { $0.id == item.workspaceId }) else { continue }
                let meta = metadataMap[item.workspaceId]
                item.refresh(workspace: ws,
                             isSelected: ws.id == selectedId,
                             metadata: meta,
                             status: workspaceStatus(ws),
                             theme: theme,
                             backgroundOpacity: backgroundOpacity,
                             showStatusIndicators: showStatusIndicators)
            }
            return
        }

        existing.forEach { $0.removeFromSuperview() }
        for ws in workspaces {
            let meta = metadataMap[ws.id]
            let item = WorkspaceRowItemView(
                workspace: ws,
                isSelected: ws.id == selectedId,
                metadata: meta,
                status: workspaceStatus(ws),
                theme: theme,
                backgroundOpacity: backgroundOpacity,
                showStatusIndicators: showStatusIndicators
            )
            wireRowCallbacks(item)
            rowsContainer.addSubview(item)
        }
        layoutRows(animated: false)
    }

    private func wireRowCallbacks(_ item: WorkspaceRowItemView) {
        let id = item.workspaceId
        item.onSelect             = { [weak self] in self?.onSelect?(id) }
        item.onRename              = { [weak self] new in self?.onRename?(id, new) }
        item.onRequestDelete       = { [weak self] in self?.onRequestDelete?(id) }
        item.onRequestEditCommand  = { [weak self] current in self?.onRequestEditCommand?(id, current) }
        item.onDragEnded           = { [weak self] in self?.cleanupAfterDrag() }
    }

    fileprivate func cleanupAfterDrag() {
        guard draggingId != nil || previewInsertionIndex != nil else { return }
        draggingId = nil
        previewInsertionIndex = nil
        rowsContainer.subviews
            .compactMap { $0 as? WorkspaceRowItemView }
            .forEach { $0.isDragGhost = false }
        layoutRows(animated: true)
    }

    /// Compute the row order to render, factoring in any drag preview.
    private func previewOrdered(items: [WorkspaceRowItemView]) -> [WorkspaceRowItemView] {
        guard let draggingId,
              let insertion = previewInsertionIndex,
              let fromIdx = items.firstIndex(where: { $0.workspaceId == draggingId })
        else { return items }

        var copy = items
        let picked = copy.remove(at: fromIdx)
        // `insertion` uses "before index" semantics. Removing the dragged
        // item shifts every index > fromIdx down by 1.
        let dest = insertion > fromIdx ? insertion - 1 : insertion
        copy.insert(picked, at: max(0, min(copy.count, dest)))
        return copy
    }

    /// Hit-test the cursor's y to a 0…count insertion index. Uses each
    /// row's current frame midpoint, so the drag target slot grows /
    /// shrinks naturally with the variable row heights driven by
    /// `defaultCommand` text wrap.
    private func insertionIndex(at pointInSelf: NSPoint) -> Int {
        guard !workspaces.isEmpty else { return 0 }
        let pointInContainer = rowsContainer.convert(pointInSelf, from: self)
        let rows = rowsContainer.subviews
            .compactMap { $0 as? WorkspaceRowItemView }
            .sorted { $0.frame.minY < $1.frame.minY }
        for (idx, row) in rows.enumerated() {
            if pointInContainer.y < row.frame.midY { return idx }
        }
        return workspaces.count
    }

    fileprivate func layoutRows(animated: Bool = false) {
        let items = rowsContainer.subviews.compactMap { $0 as? WorkspaceRowItemView }
        let ordered = previewOrdered(items: items)
        let w = max(0, scrollView.contentSize.width - Self.outerHorizontalInset * 2)
        let heights = ordered.map { $0.preferredHeight(forWidth: w) }
        let totalH = heights.reduce(0, +) + CGFloat(max(0, ordered.count - 1)) * Self.rowSpacing
        let containerH = max(totalH, scrollView.contentSize.height)

        let apply = {
            var y: CGFloat = 0
            for (idx, item) in ordered.enumerated() {
                let h = heights[idx]
                let frame = NSRect(x: Self.outerHorizontalInset, y: y, width: w, height: h)
                if animated {
                    item.animator().frame = frame
                } else {
                    item.frame = frame
                }
                item.isDragGhost = (item.workspaceId == self.draggingId)
                y += h + Self.rowSpacing
            }
            self.rowsContainer.frame = NSRect(
                x: 0, y: 0,
                width: self.scrollView.contentSize.width,
                height: containerH
            )
        }
        if animated {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.16
                ctx.allowsImplicitAnimation = true
                apply()
            }
        } else {
            apply()
        }
    }

    // MARK: - NSDraggingDestination

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        if let raw = sender.draggingPasteboard.string(forType: .in0Workspace),
           let uuid = UUID(uuidString: raw) {
            draggingId = uuid
        }
        return draggingUpdated(sender)
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard sender.draggingPasteboard.types?.contains(.in0Workspace) == true else { return [] }
        let pointInSelf = convert(sender.draggingLocation, from: nil)
        let idx = insertionIndex(at: pointInSelf)
        if idx != previewInsertionIndex {
            previewInsertionIndex = idx
            layoutRows(animated: true)
        }
        if let event = NSApp.currentEvent {
            scrollView.contentView.autoscroll(with: event)
        }
        return .move
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        if previewInsertionIndex != nil {
            previewInsertionIndex = nil
            layoutRows(animated: true)
        }
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let raw = sender.draggingPasteboard.string(forType: .in0Workspace),
              let uuid = UUID(uuidString: raw),
              let from = workspaces.firstIndex(where: { $0.id == uuid })
        else {
            cleanupAfterDrag()
            return false
        }
        let pointInSelf = convert(sender.draggingLocation, from: nil)
        let to = insertionIndex(at: pointInSelf)
        onReorder?(from, to)
        cleanupAfterDrag()
        return true
    }

    /// Hook for the SwiftUI bridge to call after a `LanguageStore.tick`
    /// change. Today's row content is either user-given (workspace name)
    /// or dynamic from metadata (branch / PR badge), so there's nothing
    /// to rebind here — kept as a stable refresh seam.
    func refreshLocalizedStrings() {
        // intentional no-op
    }
}

// MARK: - WorkspaceRowItemView

private final class WorkspaceRowItemView: NSView, NSTextFieldDelegate, NSDraggingSource {
    let workspaceId: UUID

    var onSelect: (() -> Void)?
    var onRename: ((String) -> Void)?
    var onRequestDelete: (() -> Void)?
    /// Bubbles the current default-command string upward so the SwiftUI
    /// shell can seed its alert's text field.
    var onRequestEditCommand: ((String) -> Void)?
    var onDragEnded: (() -> Void)?

    var isDragGhost: Bool = false {
        didSet {
            guard oldValue != isDragGhost else { return }
            alphaValue = isDragGhost ? 0.35 : 1
        }
    }

    private let backgroundLayerView = NSView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let branchLabel = NSTextField(labelWithString: "")
    private let commandLabel = NSTextField(labelWithString: "")
    private let prBadge = NSTextField(labelWithString: "")
    private let statusIcon = TerminalStatusIconView(frame: .zero)
    fileprivate let renameField = NSTextField()

    fileprivate var isSelected: Bool
    fileprivate var isHovered = false
    fileprivate var isRenaming = false
    fileprivate var theme: AppTheme
    fileprivate var backgroundOpacity: CGFloat
    fileprivate var showStatusIndicators: Bool
    private var workspace: Workspace
    private var metadata: WorkspaceMetadataSnapshot?
    private var status: TerminalStatus
    fileprivate var originalTitle: String = ""

    init(workspace: Workspace,
         isSelected: Bool,
         metadata: WorkspaceMetadataSnapshot?,
         status: TerminalStatus = .neverRan,
         theme: AppTheme,
         backgroundOpacity: CGFloat = 1.0,
         showStatusIndicators: Bool = false) {
        self.workspaceId = workspace.id
        self.workspace = workspace
        self.isSelected = isSelected
        self.metadata = metadata
        self.status = status
        self.theme = theme
        self.backgroundOpacity = backgroundOpacity
        self.showStatusIndicators = showStatusIndicators
        super.init(frame: .zero)
        setup()
        updateContent()
        updateStyle()
        statusIcon.isHidden = !showStatusIndicators
        statusIcon.update(status: status, theme: theme)
    }
    required init?(coder: NSCoder) { fatalError("not supported") }

    private func setup() {
        wantsLayer = true

        backgroundLayerView.wantsLayer = true
        backgroundLayerView.layer?.cornerRadius = DT.Radius.row
        backgroundLayerView.layer?.masksToBounds = true
        addSubview(backgroundLayerView)

        for label in [titleLabel, branchLabel, commandLabel, prBadge] {
            label.isBezeled = false
            label.drawsBackground = false
            label.isEditable = false
            label.isSelectable = false
            addSubview(label)
        }
        titleLabel.lineBreakMode = .byTruncatingTail
        branchLabel.lineBreakMode = .byTruncatingMiddle
        branchLabel.font = DT.Font.mono
        commandLabel.lineBreakMode = .byWordWrapping
        commandLabel.maximumNumberOfLines = 3
        commandLabel.font = DT.Font.mono
        prBadge.font = DT.Font.micro

        addSubview(statusIcon)

        renameField.isBezeled = false
        renameField.drawsBackground = false
        renameField.isEditable = true
        renameField.isSelectable = true
        renameField.focusRingType = .none
        renameField.isHidden = true
        renameField.delegate = self
        renameField.font = DT.Font.body
        addSubview(renameField)
    }

    override func layout() {
        super.layout()
        backgroundLayerView.frame = bounds

        let hPad = DT.Space.md
        let topPad = DT.Space.xs
        let titleH = ceil(titleLabel.intrinsicContentSize.height)
        let branchH = ceil(branchLabel.intrinsicContentSize.height)

        let iconSize: CGFloat = showStatusIndicators ? TerminalStatusIconView.size : 0
        if showStatusIndicators {
            statusIcon.frame = NSRect(
                x: bounds.width - hPad - iconSize,
                y: bounds.height - topPad - titleH + (titleH - iconSize) / 2,
                width: iconSize, height: iconSize
            )
        }

        let prW: CGFloat = prBadge.isHidden
            ? 0
            : ceil(prBadge.intrinsicContentSize.width) + DT.Space.xs
        let iconSlotW: CGFloat = showStatusIndicators ? (iconSize + DT.Space.xs) : 0

        let titleFrame = NSRect(
            x: hPad,
            y: bounds.height - topPad - titleH,
            width: bounds.width - hPad * 2 - prW - iconSlotW,
            height: titleH
        )
        titleLabel.frame = titleFrame
        renameField.frame = titleFrame
        renameField.font = titleLabel.font

        if !prBadge.isHidden {
            prBadge.frame = NSRect(
                x: bounds.width - hPad - iconSize - DT.Space.xs - prW + DT.Space.xs,
                y: bounds.height - topPad - titleH,
                width: prW, height: titleH
            )
        }

        // Command vs branch — mutually exclusive; one of them stacks
        // directly below the title to form the row's title pair.
        let pairGap = DT.Space.xs
        if !commandLabel.isHidden {
            let cmdH = commandLabelHeight(forWidth: bounds.width - hPad * 2)
            commandLabel.frame = NSRect(
                x: hPad,
                y: max(topPad, titleFrame.minY - pairGap - cmdH),
                width: bounds.width - hPad * 2,
                height: cmdH
            )
        } else if !branchLabel.isHidden {
            branchLabel.frame = NSRect(
                x: hPad,
                y: max(topPad, titleFrame.minY - pairGap - branchH),
                width: bounds.width - hPad * 2,
                height: branchH
            )
        }
    }

    fileprivate func preferredHeight(forWidth width: CGFloat) -> CGFloat {
        guard workspace.defaultCommand?.isEmpty == false else {
            return WorkspaceListView.baseRowHeight
        }
        let contentWidth = max(0, width - DT.Space.md * 2)
        let titleH = ceil(titleLabel.intrinsicContentSize.height)
        let commandH = commandLabelHeight(forWidth: contentWidth)
        return max(
            WorkspaceListView.baseRowHeight,
            DT.Space.xs + titleH + DT.Space.xs + commandH
        )
    }

    private func commandLabelHeight(forWidth width: CGFloat) -> CGFloat {
        guard !commandLabel.stringValue.isEmpty else { return 0 }
        let font = commandLabel.font ?? DT.Font.mono
        let attr = NSAttributedString(string: commandLabel.stringValue, attributes: [.font: font])
        let measured = attr.boundingRect(
            with: NSSize(width: max(1, width), height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        ).height
        let lineHeight = ceil(font.boundingRectForFont.height)
        return min(ceil(measured), lineHeight * 3)
    }

    func refresh(workspace: Workspace,
                 isSelected: Bool,
                 metadata: WorkspaceMetadataSnapshot?,
                 status: TerminalStatus = .neverRan,
                 theme: AppTheme,
                 backgroundOpacity: CGFloat = 1.0,
                 showStatusIndicators: Bool = false) {
        self.workspace = workspace
        self.isSelected = isSelected
        self.metadata = metadata
        self.status = status
        self.theme = theme
        self.backgroundOpacity = backgroundOpacity
        self.showStatusIndicators = showStatusIndicators
        if !isRenaming, titleLabel.stringValue != workspace.name {
            titleLabel.stringValue = workspace.name
        }
        updateContent()
        updateStyle()
        statusIcon.isHidden = !showStatusIndicators
        statusIcon.update(status: status, theme: theme)
        needsLayout = true
    }

    func applyTheme(_ theme: AppTheme, backgroundOpacity: CGFloat = 1.0) {
        self.theme = theme
        self.backgroundOpacity = backgroundOpacity
        updateStyle()
        statusIcon.update(status: status, theme: theme)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach { removeTrackingArea($0) }
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseEnteredAndExited, .inVisibleRect],
            owner: self
        ))
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        updateStyle()
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        updateStyle()
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func resetCursorRects() {
        // While renaming, defer to the field editor's I-beam cursor.
        guard !isRenaming else { return }
        addCursorRect(bounds, cursor: .pointingHand)
    }

    fileprivate var mouseDownLocation: NSPoint = .zero

    override func mouseDown(with event: NSEvent) {
        mouseDownLocation = event.locationInWindow
        onSelect?()
    }

    override func rightMouseDown(with event: NSEvent) {
        let menu = NSMenu()
        menu.autoenablesItems = false

        let rename = NSMenuItem(title: L10n.string("sidebar.row.rename"),
                                action: #selector(beginRenameAction), keyEquivalent: "")
        rename.target = self
        menu.addItem(rename)

        let cmd = NSMenuItem(title: L10n.string("sidebar.row.commandPanel.editTitle"),
                             action: #selector(requestEditCommandAction), keyEquivalent: "")
        cmd.target = self
        menu.addItem(cmd)

        menu.addItem(.separator())

        let del = NSMenuItem(title: L10n.string("sidebar.row.delete"),
                             action: #selector(deleteAction), keyEquivalent: "")
        del.target = self
        menu.addItem(del)

        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    @objc fileprivate func deleteAction() { onRequestDelete?() }
    @objc private func requestEditCommandAction() {
        onRequestEditCommand?(workspace.defaultCommand ?? "")
    }

    @objc fileprivate func beginRenameAction() {
        guard !isRenaming else { return }
        originalTitle = titleLabel.stringValue
        renameField.stringValue = originalTitle
        titleLabel.isHidden = true
        renameField.isHidden = false
        isRenaming = true
        window?.makeFirstResponder(renameField)
        renameField.currentEditor()?.selectAll(nil)
        window?.invalidateCursorRects(for: self)
    }

    private func finishRenameUI() {
        renameField.isHidden = true
        titleLabel.isHidden = false
        isRenaming = false
        window?.invalidateCursorRects(for: self)
    }

    private func commitRename() {
        guard isRenaming else { return }
        let new = renameField.stringValue
        finishRenameUI()
        onRename?(new)
    }

    private func cancelRename() {
        guard isRenaming else { return }
        renameField.stringValue = originalTitle
        finishRenameUI()
    }

    // NSTextFieldDelegate

    func control(_ control: NSControl, textView: NSTextView,
                 doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            cancelRename()
            return true
        }
        return false
    }

    func controlTextDidEndEditing(_ notification: Notification) {
        // Enter + focus-loss both come here; Esc bailed in doCommandBy.
        commitRename()
    }

    override func mouseDragged(with event: NSEvent) {
        if isRenaming { return }
        let dx = event.locationInWindow.x - mouseDownLocation.x
        let dy = event.locationInWindow.y - mouseDownLocation.y
        guard (dx * dx + dy * dy) > 16 else { return }   // 4 pt threshold

        let item = NSPasteboardItem()
        item.setString(workspaceId.uuidString, forType: .in0Workspace)

        let (ghost, frame) = snapshotForDragging()
        let dragItem = NSDraggingItem(pasteboardWriter: item)
        dragItem.setDraggingFrame(frame, contents: ghost)

        beginDraggingSession(with: [dragItem], event: event, source: self)
    }

    private func snapshotForDragging() -> (image: NSImage, frame: NSRect) {
        guard let rep = bitmapImageRepForCachingDisplay(in: bounds) else {
            return (NSImage(), bounds)
        }
        cacheDisplay(in: bounds, to: rep)
        let raw = NSImage(size: bounds.size)
        raw.addRepresentation(rep)
        return DraggedSnapshotShadow.compose(
            content: raw, contentSize: bounds.size, cornerRadius: DT.Radius.row
        )
    }

    // NSDraggingSource

    func draggingSession(_ session: NSDraggingSession,
                         sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        .move
    }

    func draggingSession(_ session: NSDraggingSession,
                         endedAt screenPoint: NSPoint,
                         operation: NSDragOperation) {
        onDragEnded?()
    }

    private func updateContent() {
        titleLabel.stringValue = workspace.name
        let hasCommand = (workspace.defaultCommand?.isEmpty == false)
        if hasCommand, let cmd = workspace.defaultCommand {
            commandLabel.stringValue = "$ \(cmd)"
            commandLabel.isHidden = false
        } else {
            commandLabel.stringValue = ""
            commandLabel.isHidden = true
        }
        if !hasCommand, let branch = metadata?.gitBranch {
            branchLabel.stringValue = "⎇ \(branch)"
            branchLabel.isHidden = false
        } else {
            branchLabel.stringValue = ""
            branchLabel.isHidden = true
        }
        if let pr = metadata?.prStatus {
            prBadge.stringValue = pr.uppercased()
            prBadge.isHidden = false
        } else {
            prBadge.stringValue = ""
            prBadge.isHidden = true
        }
    }

    fileprivate func updateStyle() {
        let fill: NSColor
        if isSelected {
            fill = theme.borderNS.withAlphaComponent(backgroundOpacity)
            titleLabel.textColor = theme.foregroundNS
        } else if isHovered {
            fill = theme.borderNS.withAlphaComponent(backgroundOpacity)
            titleLabel.textColor = theme.textSecondaryNS
        } else {
            fill = .clear
            titleLabel.textColor = theme.textSecondaryNS
        }
        backgroundLayerView.layer?.backgroundColor = fill.cgColor
        titleLabel.font = DT.Font.body
        branchLabel.textColor = theme.textTertiaryNS
        commandLabel.textColor = theme.textTertiaryNS
        prBadge.textColor = theme.textTertiaryNS
        renameField.textColor = theme.foregroundNS
        needsDisplay = true
    }
}
