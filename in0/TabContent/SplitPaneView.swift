import AppKit

/// NSView that renders a SplitNode tree as nested NSSplitViews. Re-renders
/// only when the tree's *structure* changes (see `SplitNode.sameStructure`);
/// pure-ratio updates are pushed to existing dividers without rebuild.
@MainActor
final class SplitPaneView: NSView {
    let tabId: UUID
    private weak var cache: SurfaceCache?
    private let onRatioChange: (UUID, Double) -> Void
    private let onPaneFocus: (UUID) -> Void
    var onTabDropOnPane: ((_ droppedTabId: UUID, _ ontoTerminalId: UUID, _ edge: NSRectEdge) -> Void)?

    private var currentLayout: SplitNode?
    private var rootChild: NSView?
    private var paneWrappers: [UUID: ClickRoutingView] = [:]
    private var focusedId: UUID?

    private static var unfocusedAlpha: CGFloat = 0.55

    init(
        tabId: UUID,
        cache: SurfaceCache,
        onRatioChange: @escaping (UUID, Double) -> Void,
        onPaneFocus: @escaping (UUID) -> Void
    ) {
        self.tabId = tabId
        self.cache = cache
        self.onRatioChange = onRatioChange
        self.onPaneFocus = onPaneFocus
        super.init(frame: .zero)
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError("not supported") }

    func apply(layout: SplitNode) {
        if let cur = currentLayout, cur.sameStructure(as: layout) {
            // Same shape; just push new ratios.
            updateRatios(in: rootChild, against: layout)
            currentLayout = layout
            return
        }
        rebuild(with: layout)
        currentLayout = layout
    }

    func focusTerminal(_ terminalId: UUID) {
        focusedId = terminalId
        applyFocusAlpha()
        cache?.view(for: terminalId).focusTerminal()
    }

    static func setUnfocusedAlpha(_ value: CGFloat) {
        unfocusedAlpha = max(0, min(1, value))
    }

    private func applyFocusAlpha() {
        let only1 = paneWrappers.count <= 1
        for (id, wrapper) in paneWrappers {
            wrapper.alphaValue = (only1 || id == focusedId) ? 1.0 : Self.unfocusedAlpha
        }
    }

    private func rebuild(with layout: SplitNode) {
        rootChild?.removeFromSuperview()
        paneWrappers.removeAll()
        let child = makeChild(for: layout)
        applyFocusAlpha()
        addSubview(child)
        child.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            child.leadingAnchor.constraint(equalTo: leadingAnchor),
            child.trailingAnchor.constraint(equalTo: trailingAnchor),
            child.topAnchor.constraint(equalTo: topAnchor),
            child.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        rootChild = child
    }

    private func makeChild(for node: SplitNode) -> NSView {
        switch node {
        case .terminal(let id):
            guard let cache else { return NSView() }
            let view = cache.view(for: id)
            // Wrap the terminal in a SurfaceScrollView (native NSScrollView +
            // overlay scroller, syncs to ghostty's SCROLLBAR action), then in
            // a ClickRoutingView (focus routing + tab-drop target).
            let scroller = SurfaceScrollView(terminalView: view)
            let wrapper = ClickRoutingView(target: id, onClick: onPaneFocus)
            wrapper.wantsLayer = true
            wrapper.onTabDrop = { [weak self] droppedTabId, ontoTermId, edge in
                self?.onTabDropOnPane?(droppedTabId, ontoTermId, edge)
            }
            paneWrappers[id] = wrapper
            wrapper.addSubview(scroller)
            scroller.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                scroller.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor),
                scroller.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor),
                scroller.topAnchor.constraint(equalTo: wrapper.topAnchor),
                scroller.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor),
            ])
            return wrapper

        case .split(let sid, let dir, let r, let a, let b):
            let split = NSSplitView()
            split.dividerStyle = .thin
            split.isVertical = (dir == .vertical)
            split.translatesAutoresizingMaskIntoConstraints = false
            split.addArrangedSubview(makeChild(for: a))
            split.addArrangedSubview(makeChild(for: b))

            let delegate = SplitDelegate(
                splitId: sid,
                ratio: r,
                onRatioChange: onRatioChange
            )
            split.delegate = delegate
            // Retain delegate via associated reference.
            objc_setAssociatedObject(split, &SplitPaneView.delegateKey, delegate, .OBJC_ASSOCIATION_RETAIN)

            // Apply initial ratio after the view has a frame.
            DispatchQueue.main.async {
                let total = split.isVertical ? split.bounds.width : split.bounds.height
                if total > 0 {
                    split.setPosition(total * CGFloat(r), ofDividerAt: 0)
                }
            }
            return split
        }
    }

    private nonisolated(unsafe) static var delegateKey: UInt8 = 0

    private func updateRatios(in view: NSView?, against node: SplitNode) {
        guard let view else { return }
        if let split = view as? NSSplitView,
           case .split(_, _, let r, let a, let b) = node {
            let total = split.isVertical ? split.bounds.width : split.bounds.height
            if total > 0 {
                split.setPosition(total * CGFloat(r), ofDividerAt: 0)
            }
            let kids = split.arrangedSubviews
            if kids.count == 2 {
                updateRatios(in: kids[0], against: a)
                updateRatios(in: kids[1], against: b)
            }
        }
    }
}

/// Transparent wrapper that forwards mouseDown to focus routing without
/// stealing the click from ghostty's own input handling. Also a drop target
/// for tab drags — releasing a tab over a pane forms a new split.
// .in0Tab UTI lives in PasteboardTypes.swift

final class ClickRoutingView: NSView {
    let targetTerminalId: UUID
    let onClick: (UUID) -> Void
    /// Called when a tab is dropped onto this pane. The host (TabBridge) is
    /// expected to remove the tab and graft its surface into a new split.
    var onTabDrop: ((_ droppedTabId: UUID, _ ontoTerminalId: UUID, _ edge: NSRectEdge) -> Void)?

    init(target: UUID, onClick: @escaping (UUID) -> Void) {
        self.targetTerminalId = target
        self.onClick = onClick
        super.init(frame: .zero)
        registerForDraggedTypes([NSPasteboard.PasteboardType.in0Tab])
    }
    required init?(coder: NSCoder) { fatalError("not supported") }

    override func mouseDown(with event: NSEvent) {
        onClick(targetTerminalId)
        // The terminal is wrapped by SurfaceScrollView for native scrolling;
        // dig down to find it instead of expecting a direct child.
        if let scroller = subviews.first as? SurfaceScrollView {
            scroller.terminalView.focusTerminal()
        } else if let terminalView = subviews.first as? GhosttyTerminalView {
            terminalView.focusTerminal()
        }
        super.mouseDown(with: event)
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        sender.draggingPasteboard.string(forType: NSPasteboard.PasteboardType.in0Tab) != nil ? .move : []
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let raw = sender.draggingPasteboard.string(forType: NSPasteboard.PasteboardType.in0Tab),
              let droppedTabId = UUID(uuidString: raw) else { return false }
        let local = convert(sender.draggingLocation, from: nil)
        let edge = edgeForPoint(local)
        onTabDrop?(droppedTabId, targetTerminalId, edge)
        return true
    }

    private func edgeForPoint(_ point: NSPoint) -> NSRectEdge {
        let w = bounds.width, h = bounds.height
        let relX = point.x / max(w, 1)
        let relY = point.y / max(h, 1)
        let dxLeft = relX, dxRight = 1 - relX
        let dyBottom = relY, dyTop = 1 - relY
        let minH = min(dxLeft, dxRight), minV = min(dyBottom, dyTop)
        if minH < minV {
            return dxLeft < dxRight ? .minX : .maxX
        } else {
            return dyBottom < dyTop ? .minY : .maxY
        }
    }
}

/// NSSplitView delegate that emits ratio updates and lets both panes shrink
/// to a sensible minimum.
private final class SplitDelegate: NSObject, NSSplitViewDelegate {
    let splitId: UUID
    var lastSentRatio: Double
    let onRatioChange: (UUID, Double) -> Void

    init(splitId: UUID, ratio: Double, onRatioChange: @escaping (UUID, Double) -> Void) {
        self.splitId = splitId
        self.lastSentRatio = ratio
        self.onRatioChange = onRatioChange
    }

    func splitView(_ splitView: NSSplitView, constrainMinCoordinate proposedMinimumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
        return 80
    }

    func splitView(_ splitView: NSSplitView, constrainMaxCoordinate proposedMaximumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
        let total = splitView.isVertical ? splitView.bounds.width : splitView.bounds.height
        return max(total - 80, 80)
    }

    func splitViewDidResizeSubviews(_ notification: Notification) {
        guard let split = notification.object as? NSSplitView,
              let first = split.arrangedSubviews.first else { return }
        let total = split.isVertical ? split.bounds.width : split.bounds.height
        let firstSize = split.isVertical ? first.bounds.width : first.bounds.height
        guard total > 0 else { return }
        let ratio = Double(firstSize / total)
        if abs(ratio - lastSentRatio) > 0.005 {
            lastSentRatio = ratio
            onRatioChange(splitId, ratio)
        }
    }
}
