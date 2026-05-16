import AppKit

/// Wraps a `GhosttyTerminalView` inside an `NSScrollView` so the user gets
/// the native macOS overlay scroller (thumb hover, fluid drag, two-finger
/// scroll inertia) instead of a static painted bar.
///
/// **Architecture** (ported from upstream ghostty's macOS host):
/// - `scrollView`   — outer NSScrollView, always overlay style, transparent.
/// - `documentView` — blank NSView whose height equals total scrollback
///                    rows × cell height. Never rendered; only sized.
/// - `terminalView` — the actual Metal-backed surface, kept pinned to the
///                    clip view's `documentVisibleRect` so ghostty only
///                    renders the viewport, never the full scrollback.
///
/// **Coordinate inversion**: terminal rows count from the top (row 0 is the
/// oldest line); AppKit's y axis grows upward. So the y offset of the
/// viewport inside documentView is `(total - offset - len) * cellHeight`.
///
/// State flows in two directions:
/// 1. Ghostty → us: `SCROLLBAR` and `CELL_SIZE` actions update
///    `GhosttyTerminalView`'s stored state and post notifications; we
///    re-sync the document view + clip view origin.
/// 2. User → ghostty: live drags convert the new scroll position back into
///    a row index and fire `scroll_to_row:N` via the binding action.
///
/// Why we force overlay scrollers: legacy (always-visible) scrollers would
/// shave horizontal points off the ghostty surface every time they toggle
/// on/off, kicking the PTY into a reflow storm. Overlay style draws over
/// the surface and never resizes it.
final class SurfaceScrollView: NSView {

    let terminalView: GhosttyTerminalView

    private let scrollView = NSScrollView()
    private let documentView = NSView(frame: .zero)
    private var observers: [NSObjectProtocol] = []
    private var isLiveScrolling = false
    /// Last row we sent through `scroll_to_row:N`. Suppresses redundant
    /// binding-action calls when the thumb moves within a single row.
    private var lastSentRow: Int?

    init(terminalView: GhosttyTerminalView) {
        self.terminalView = terminalView
        super.init(frame: .zero)
        wantsLayer = true

        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.usesPredominantAxisScrolling = true
        scrollView.scrollerStyle = .overlay
        scrollView.drawsBackground = false
        scrollView.contentView.clipsToBounds = false

        documentView.frame.size = .zero
        scrollView.documentView = documentView

        terminalView.removeFromSuperview()
        documentView.addSubview(terminalView)
        addSubview(scrollView)

        wireObservers()
    }

    required init?(coder: NSCoder) { fatalError("not supported") }

    deinit {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
    }

    override var safeAreaInsets: NSEdgeInsets { NSEdgeInsetsZero }

    override func layout() {
        super.layout()
        scrollView.frame = bounds
        // Terminal always fills the visible viewport. `setFrameSize` on
        // `GhosttyTerminalView` cascades the new size into ghostty via
        // `ghostty_surface_set_size`.
        terminalView.frame.size = scrollView.bounds.size
        documentView.frame.size.width = scrollView.bounds.width
        synchronizeScrollView()
        synchronizeTerminalFrame()
    }

    // MARK: - Observers

    private func wireObservers() {
        let nc = NotificationCenter.default

        // Clip view bounds change → re-pin terminal subview origin.
        scrollView.contentView.postsBoundsChangedNotifications = true
        observers.append(nc.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: scrollView.contentView,
            queue: .main
        ) { [weak self] _ in self?.synchronizeTerminalFrame() })

        observers.append(nc.addObserver(
            forName: NSScrollView.willStartLiveScrollNotification,
            object: scrollView,
            queue: .main
        ) { [weak self] _ in self?.isLiveScrolling = true })

        observers.append(nc.addObserver(
            forName: NSScrollView.didEndLiveScrollNotification,
            object: scrollView,
            queue: .main
        ) { [weak self] _ in self?.isLiveScrolling = false })

        observers.append(nc.addObserver(
            forName: NSScrollView.didLiveScrollNotification,
            object: scrollView,
            queue: .main
        ) { [weak self] _ in self?.handleLiveScroll() })

        // Force overlay even if the user flips system pref to "Always".
        observers.append(nc.addObserver(
            forName: NSScroller.preferredScrollerStyleDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in self?.scrollView.scrollerStyle = .overlay })

        observers.append(nc.addObserver(
            forName: GhosttyTerminalView.scrollbarDidChangeNotification,
            object: terminalView,
            queue: .main
        ) { [weak self] _ in self?.synchronizeScrollView() })

        observers.append(nc.addObserver(
            forName: GhosttyTerminalView.cellSizeDidChangeNotification,
            object: terminalView,
            queue: .main
        ) { [weak self] _ in self?.synchronizeScrollView() })
    }

    // MARK: - Sync

    /// Re-size the blank document view to mirror total scrollback rows;
    /// unless the user is dragging, scroll so the visible portion matches
    /// ghostty's offset.
    private func synchronizeScrollView() {
        documentView.frame.size.height = documentHeight()

        if !isLiveScrolling {
            let cellH = terminalView.cellSize.height
            if cellH > 0, let sb = terminalView.scrollbarState {
                // ghostty offset = rows from top; AppKit y grows up.
                let bottomRows = Int64(sb.total) - Int64(sb.offset) - Int64(sb.len)
                let offsetY = CGFloat(max(0, bottomRows)) * cellH
                scrollView.contentView.scroll(to: CGPoint(x: 0, y: offsetY))
                lastSentRow = Int(sb.offset)
            }
        }
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    /// Pin the terminal subview to the current viewport so the Metal
    /// rendering stays glued to the visible region during scrolling.
    private func synchronizeTerminalFrame() {
        let visible = scrollView.contentView.documentVisibleRect
        terminalView.frame.origin = visible.origin
    }

    /// While the user drags the scroller: read the current viewport, map
    /// back to a row index, fire `scroll_to_row:N` (skipping no-op moves).
    private func handleLiveScroll() {
        let cellH = terminalView.cellSize.height
        guard cellH > 0 else { return }
        let visible = scrollView.contentView.documentVisibleRect
        let docH = documentView.frame.height
        let offsetFromTop = docH - visible.origin.y - visible.height
        let row = max(0, Int(offsetFromTop / cellH))
        guard row != lastSentRow else { return }
        lastSentRow = row
        terminalView.performBindingAction("scroll_to_row:\(row)")
    }

    /// Required height of the blank document view so the scroller thumb
    /// represents the correct slice of scrollback. Keeps the viewport's
    /// vertical padding so the document grid stays aligned to the cell
    /// rows once the user starts scrolling.
    private func documentHeight() -> CGFloat {
        let contentH = scrollView.contentSize.height
        let cellH = terminalView.cellSize.height
        guard cellH > 0, let sb = terminalView.scrollbarState else { return contentH }
        let gridH = CGFloat(sb.total) * cellH
        let padding = contentH - (CGFloat(sb.len) * cellH)
        return gridH + padding
    }

    // MARK: - Hover

    /// When the user has the system pref set to legacy scrollers, they
    /// expect the scroller to flash when the mouse approaches it. Force
    /// `.overlay` style means it auto-hides; flash on hover so the drag
    /// target stays discoverable.
    override func mouseMoved(with event: NSEvent) {
        guard NSScroller.preferredScrollerStyle == .legacy else { return }
        scrollView.flashScrollers()
    }

    override func updateTrackingAreas() {
        trackingAreas.forEach { removeTrackingArea($0) }
        super.updateTrackingAreas()
        guard let scroller = scrollView.verticalScroller else { return }
        addTrackingArea(NSTrackingArea(
            rect: convert(scroller.bounds, from: scroller),
            options: [.mouseMoved, .activeInKeyWindow],
            owner: self,
            userInfo: nil
        ))
    }
}
