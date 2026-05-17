import AppKit

/// NSView that hosts a single ghostty surface. Metal rendering happens on a
/// CALayer created by libghostty; this view owns layout and surface lifetime.
///
/// Surface lifecycle:
/// - created lazily on first `viewDidMoveToWindow` where `window != nil`
/// - **not** freed when removed from a window (so view caching across tab
///   switches preserves the running shell)
/// - freed only by explicit `dispose()` from the cache owner
final class GhosttyTerminalView: NSView, @preconcurrency NSTextInputClient {
    private(set) var surface: ghostty_surface_t?
    private static let liveLock = NSLock()
    private static var live: [ObjectIdentifier: WeakTerminalView] = [:]

    /// Stable id used for persistence and pwd tracking.
    let terminalId: UUID

    private var hasEverHadWindow = false
    private var markedText = NSMutableAttributedString()
    private var markedSelectedRange = NSRange(location: NSNotFound, length: 0)
    private var keyMonitor: Any?
    private var wantsTerminalKeyEvents = false
    private var pendingSurfaceSize: SurfacePixelSize?
    private var appliedSurfaceSize: SurfacePixelSize?
    private var resizeWorkItem: DispatchWorkItem?

    /// Most recent scrollbar state reported by ghostty's `SCROLLBAR`
    /// action. `nil` until the first action arrives. `SurfaceScrollView`
    /// reads this to size its document view.
    private(set) var scrollbarState: ScrollbarState?

    /// Per-cell pixel dimensions from ghostty's `CELL_SIZE` action.
    /// Used to convert between ghostty's row-based scrollback model and
    /// AppKit's pixel-based scroll view coords.
    private(set) var cellSize: CellSize = .zero

    /// Posted on the main queue after `applyScrollbar(...)` updates state.
    static let scrollbarDidChangeNotification = Notification.Name("in0.GhosttyTerminalView.scrollbarDidChange")
    /// Posted on the main queue after `applyCellSize(...)`.
    static let cellSizeDidChangeNotification  = Notification.Name("in0.GhosttyTerminalView.cellSizeDidChange")

    struct ScrollbarState: Equatable {
        var total: UInt64
        var offset: UInt64
        var len: UInt64
    }

    struct CellSize: Equatable {
        var width: CGFloat
        var height: CGFloat
        static let zero = CellSize(width: 0, height: 0)
    }

    private struct SurfacePixelSize: Equatable {
        var width: UInt32
        var height: UInt32
    }

    init(terminalId: UUID) {
        self.terminalId = terminalId
        super.init(frame: .zero)
        wantsLayer = true
        layerContentsRedrawPolicy = .duringViewResize
        Self.register(self)
    }

    /// Called from the ghostty action callback when a `SCROLLBAR` action
    /// arrives for this surface.
    func applyScrollbar(total: UInt64, offset: UInt64, len: UInt64) {
        let new = ScrollbarState(total: total, offset: offset, len: len)
        if scrollbarState != new {
            scrollbarState = new
            NotificationCenter.default.post(
                name: Self.scrollbarDidChangeNotification, object: self
            )
        }
    }

    /// Called from the ghostty action callback when a `CELL_SIZE` action
    /// arrives. The C struct delivers pixel sizes; the SwiftUI scaling is
    /// handled by the caller via `window.backingScaleFactor`.
    func applyCellSize(widthPx: UInt32, heightPx: UInt32, scale: CGFloat) {
        let cs = CellSize(
            width: CGFloat(widthPx) / max(scale, 1),
            height: CGFloat(heightPx) / max(scale, 1)
        )
        if cellSize != cs {
            cellSize = cs
            NotificationCenter.default.post(
                name: Self.cellSizeDidChangeNotification, object: self
            )
        }
    }

    /// Send a ghostty binding action by name. Exposed publicly so
    /// `SurfaceScrollView` can fire `scroll_to_row:N` during user drags.
    @discardableResult
    func performBindingAction(_ action: String) -> Bool {
        runBindingAction(action)
    }

    required init?(coder: NSCoder) { fatalError("not supported") }

    deinit {
        Self.unregister(self)
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
        }
        resizeWorkItem?.cancel()
        if let surface {
            // dispose() should have been called; this is a safety net.
            ghostty_surface_free(surface)
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            removeKeyMonitor()
            return
        }
        installKeyMonitor()
        guard let window, surface == nil else { return }
        hasEverHadWindow = true
        let scale = window.backingScaleFactor
        // Pull the inherited pwd (if any) from `TerminalPwdStore`. Set by
        // `WorkspaceStore`'s `inheritPwdPolicy` when the user splits a
        // pane or opens a new tab, so the new shell starts in the same
        // directory the user was just in.
        let inheritedPwd = TerminalPwdStore.shared.pwd(for: terminalId)
        // Validate before handing to libghostty — passing a non-existent
        // path through to `ghostty_surface_new` is a known SIGSEGV.
        let safePwd = Self.validatedDirectory(inheritedPwd)
        surface = GhosttyBridge.shared.newSurface(
            nsView: self,
            scaleFactor: scale,
            workingDirectory: safePwd,
            extraEnv: ["IN0_TERMINAL_ID": terminalId.uuidString]
        )
        if let surface {
            // Sync initial size in case the view already has bounds.
            applySurfaceSizeNow(pixelSize(for: bounds.size, scale: scale), to: surface)
            window.makeFirstResponder(self)
            wantsTerminalKeyEvents = true
            // Drain any startup command enqueued by WorkspaceStore's
            // `startupCommandPolicy` — that hook runs the resolver at tab
            // creation time and writes its result into the queue, so the
            // surface only has to play it back.
            if let cmd = TerminalCommandQueue.shared.drain(for: terminalId) {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                    guard let self, let surface = self.surface else { return }
                    self.submitStartupCommand(cmd, to: surface)
                }
            }
            window.makeFirstResponder(self)
            wantsTerminalKeyEvents = true
        }
    }

    /// Called by the cache owner when the terminal is closed for good.
    func dispose() {
        resizeWorkItem?.cancel()
        resizeWorkItem = nil
        pendingSurfaceSize = nil
        appliedSurfaceSize = nil
        if let surface {
            ghostty_surface_free(surface)
            self.surface = nil
        }
    }

    static func allLiveSurfaces() -> [ghostty_surface_t] {
        liveLock.lock()
        defer { liveLock.unlock() }
        live = live.filter { $0.value.view != nil }
        return live.values.compactMap { $0.view?.surface }
    }

    enum SearchDirection {
        case next
        case previous

        var bindingSuffix: String {
            switch self {
            case .next: return "next"
            case .previous: return "previous"
            }
        }
    }

    @discardableResult
    static func performSearch(_ query: String, terminalId: UUID) -> Bool {
        guard let view = liveView(for: terminalId) else { return false }
        return view.runBindingAction("search:\(query)")
    }

    @discardableResult
    static func navigateSearch(_ direction: SearchDirection, terminalId: UUID) -> Bool {
        guard let view = liveView(for: terminalId) else { return false }
        return view.runBindingAction("navigate_search:\(direction.bindingSuffix)")
    }

    @discardableResult
    static func endSearch(terminalId: UUID) -> Bool {
        guard let view = liveView(for: terminalId) else { return false }
        return view.runBindingAction("end_search")
    }

    private static func liveView(for terminalId: UUID) -> GhosttyTerminalView? {
        liveLock.lock()
        defer { liveLock.unlock() }
        live = live.filter { $0.value.view != nil }
        return live.values.lazy.compactMap(\.view).first { $0.terminalId == terminalId }
    }

    private static func register(_ view: GhosttyTerminalView) {
        liveLock.lock()
        live[ObjectIdentifier(view)] = WeakTerminalView(view)
        liveLock.unlock()
    }

    private static func unregister(_ view: GhosttyTerminalView) {
        liveLock.lock()
        live.removeValue(forKey: ObjectIdentifier(view))
        liveLock.unlock()
    }

    override var acceptsFirstResponder: Bool { true }

    override func becomeFirstResponder() -> Bool {
        let became = super.becomeFirstResponder()
        if became, let surface {
            wantsTerminalKeyEvents = true
            ghostty_surface_set_focus(surface, true)
        }
        return became
    }

    override func resignFirstResponder() -> Bool {
        if let surface {
            ghostty_surface_set_focus(surface, false)
        }
        return super.resignFirstResponder()
    }

    func focusTerminal() {
        guard let window else { return }
        wantsTerminalKeyEvents = true
        window.makeFirstResponder(self)
        if let surface {
            ghostty_surface_set_focus(surface, true)
        }
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        focusTerminal()
        sendMouseButton(.press, button: .left, event: event)
    }

    override func mouseDragged(with event: NSEvent) {
        sendMousePosition(event)
    }

    override func mouseUp(with event: NSEvent) {
        sendMouseButton(.release, button: .left, event: event)
    }

    override func rightMouseDown(with event: NSEvent) {
        focusTerminal()
        sendMouseButton(.press, button: .right, event: event)
    }

    override func rightMouseDragged(with event: NSEvent) {
        sendMousePosition(event)
    }

    override func rightMouseUp(with event: NSEvent) {
        sendMouseButton(.release, button: .right, event: event)
    }

    override func otherMouseDown(with event: NSEvent) {
        focusTerminal()
        sendMouseButton(.press, button: .middle, event: event)
    }

    override func otherMouseDragged(with event: NSEvent) {
        sendMousePosition(event)
    }

    override func otherMouseUp(with event: NSEvent) {
        sendMouseButton(.release, button: .middle, event: event)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Copy", action: #selector(copy(_:)), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Paste", action: #selector(paste(_:)), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Select All", action: #selector(selectAll(_:)), keyEquivalent: ""))
        return menu
    }

    override func keyDown(with event: NSEvent) {
        guard surface != nil else {
            super.keyDown(with: event)
            return
        }
        if hasMarkedText() {
            interpretKeyEvents([event])
            return
        }
        if sendControlSequence(for: event) {
            return
        }
        if sendModifiedKeyToTerminal(for: event) {
            return
        }
        interpretKeyEvents([event])
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.command),
              let key = event.charactersIgnoringModifiers?.lowercased() else {
            return super.performKeyEquivalent(with: event)
        }
        switch key {
        case "c":
            copy(nil)
            return true
        case "v":
            paste(nil)
            return true
        case "a":
            selectAll(nil)
            return true
        default:
            return super.performKeyEquivalent(with: event)
        }
    }

    @objc func paste(_ sender: Any?) {
        _ = runBindingAction("paste_from_clipboard")
    }

    /// Copy selector for the Edit menu's responder-chain dispatch. Forwards
    /// to ghostty's `copy_to_clipboard` binding so selection + system
    /// clipboard semantics match ghostty's own behavior. No-op (returns
    /// false) when there's nothing selected.
    @objc func copy(_ sender: Any?) {
        _ = runBindingAction("copy_to_clipboard")
    }

    /// Select-All selector. NSResponder declares `selectAll(_:)` already,
    /// so `override` is required; otherwise AppKit's default would forward
    /// up the chain or beep.
    @objc override func selectAll(_ sender: Any?) {
        _ = runBindingAction("select_all")
    }

    @discardableResult
    private func runBindingAction(_ action: String) -> Bool {
        guard let surface else { return false }
        return action.withCString { ptr in
            ghostty_surface_binding_action(surface, ptr, UInt(action.utf8.count))
        }
    }

    func insertText(_ string: Any, replacementRange: NSRange) {
        guard let text = committedText(from: string), !text.isEmpty else { return }
        unmarkText()
        guard let surface else { return }
        sendText(text, to: surface)
    }

    override func doCommand(by selector: Selector) {
        guard let surface else {
            super.doCommand(by: selector)
            return
        }

        let text: String?
        switch selector {
        case #selector(insertNewline(_:)):
            text = "\r"
        case #selector(insertTab(_:)):
            text = "\t"
        case #selector(deleteBackward(_:)):
            text = "\u{7f}"
        case #selector(deleteForward(_:)):
            text = "\u{1b}[3~"
        case #selector(cancelOperation(_:)):
            text = "\u{1b}"
        case #selector(moveLeft(_:)):
            text = "\u{1b}[D"
        case #selector(moveRight(_:)):
            text = "\u{1b}[C"
        case #selector(moveUp(_:)):
            text = "\u{1b}[A"
        case #selector(moveDown(_:)):
            text = "\u{1b}[B"
        case #selector(moveToBeginningOfLine(_:)):
            text = "\u{1b}[H"
        case #selector(moveToEndOfLine(_:)):
            text = "\u{1b}[F"
        default:
            text = nil
        }

        guard let text else {
            super.doCommand(by: selector)
            return
        }
        sendText(text, to: surface)
    }

    private func sendControlSequence(for event: NSEvent) -> Bool {
        guard let surface else { return false }

        let controlText: String?
        switch event.keyCode {
        case 36, 76:
            controlText = "\r"
        case 48:
            controlText = "\t"
        case 51:
            controlText = "\u{7f}"
        case 53:
            controlText = "\u{1b}"
        case 117:
            controlText = "\u{1b}[3~"
        case 123:
            controlText = "\u{1b}[D"
        case 124:
            controlText = "\u{1b}[C"
        case 125:
            controlText = "\u{1b}[B"
        case 126:
            controlText = "\u{1b}[A"
        case 115:
            controlText = "\u{1b}[H"
        case 119:
            controlText = "\u{1b}[F"
        default:
            controlText = nil
        }

        guard let controlText else { return false }
        controlText.withCString { ptr in
            sendKey(event, text: ptr, to: surface)
        }
        return true
    }

    private func sendModifiedKeyToTerminal(for event: NSEvent) -> Bool {
        guard let surface,
              Self.shouldForwardModifiedKeyToTerminal(modifierFlags: event.modifierFlags) else { return false }
        sendKey(event, text: nil, to: surface)
        return true
    }

    static func shouldForwardModifiedKeyToTerminal(modifierFlags: NSEvent.ModifierFlags) -> Bool {
        let flags = modifierFlags.intersection(.deviceIndependentFlagsMask)
        return flags.contains(.control) && !flags.contains(.command)
    }

    private func sendKey(_ event: NSEvent, text: UnsafePointer<CChar>?, to surface: ghostty_surface_t) {
        let input = ghostty_input_key_s(
            action: GHOSTTY_ACTION_PRESS,
            mods: inputMods(from: event),
            consumed_mods: consumedMods(from: event),
            keycode: UInt32(event.keyCode),
            text: text,
            unshifted_codepoint: unshiftedCodepoint(from: event),
            composing: false
        )
        _ = ghostty_surface_key(surface, input)
    }

    private enum MouseState {
        case press
        case release

        var ghosttyState: ghostty_input_mouse_state_e {
            switch self {
            case .press: return GHOSTTY_MOUSE_PRESS
            case .release: return GHOSTTY_MOUSE_RELEASE
            }
        }
    }

    private enum MouseButton {
        case left
        case right
        case middle

        var ghosttyButton: ghostty_input_mouse_button_e {
            switch self {
            case .left: return GHOSTTY_MOUSE_LEFT
            case .right: return GHOSTTY_MOUSE_RIGHT
            case .middle: return GHOSTTY_MOUSE_MIDDLE
            }
        }
    }

    private func sendMouseButton(_ state: MouseState, button: MouseButton, event: NSEvent) {
        guard let surface else { return }
        let point = ghosttyPoint(from: event)
        let mods = inputMods(from: event)
        ghostty_surface_mouse_pos(surface, point.x, point.y, mods)
        _ = ghostty_surface_mouse_button(surface, state.ghosttyState, button.ghosttyButton, mods)
    }

    private func sendMousePosition(_ event: NSEvent) {
        guard let surface else { return }
        let point = ghosttyPoint(from: event)
        ghostty_surface_mouse_pos(surface, point.x, point.y, inputMods(from: event))
    }

    private func ghosttyPoint(from event: NSEvent) -> NSPoint {
        let local = convert(event.locationInWindow, from: nil)
        return NSPoint(x: local.x, y: bounds.height - local.y)
    }

    private func submitStartupCommand(_ command: String, to surface: ghostty_surface_t) {
        sendText(command, to: surface)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            guard let self, self.surface == surface else { return }
            self.sendReturnKey(to: surface)
        }
    }

    private func sendReturnKey(to surface: ghostty_surface_t) {
        "\r".withCString { ptr in
            let input = ghostty_input_key_s(
                action: GHOSTTY_ACTION_PRESS,
                mods: GHOSTTY_MODS_NONE,
                consumed_mods: GHOSTTY_MODS_NONE,
                keycode: 36,
                text: ptr,
                unshifted_codepoint: 0,
                composing: false
            )
            _ = ghostty_surface_key(surface, input)
        }
    }

    private func inputMods(from event: NSEvent) -> ghostty_input_mods_e {
        ghosttyMods(from: event.modifierFlags)
    }

    private func consumedMods(from event: NSEvent) -> ghostty_input_mods_e {
        ghosttyMods(from: event.modifierFlags.subtracting([.control, .command]))
    }

    private func ghosttyMods(from flags: NSEvent.ModifierFlags) -> ghostty_input_mods_e {
        var mods = GHOSTTY_MODS_NONE
        if flags.contains(.shift) {
            mods = ghostty_input_mods_e(rawValue: mods.rawValue | GHOSTTY_MODS_SHIFT.rawValue)
        }
        if flags.contains(.control) {
            mods = ghostty_input_mods_e(rawValue: mods.rawValue | GHOSTTY_MODS_CTRL.rawValue)
        }
        if flags.contains(.option) {
            mods = ghostty_input_mods_e(rawValue: mods.rawValue | GHOSTTY_MODS_ALT.rawValue)
        }
        if flags.contains(.command) {
            mods = ghostty_input_mods_e(rawValue: mods.rawValue | GHOSTTY_MODS_SUPER.rawValue)
        }
        if flags.contains(.capsLock) {
            mods = ghostty_input_mods_e(rawValue: mods.rawValue | GHOSTTY_MODS_CAPS.rawValue)
        }
        return mods
    }

    private func unshiftedCodepoint(from event: NSEvent) -> UInt32 {
        event.characters(byApplyingModifiers: [])?.unicodeScalars.first?.value ?? 0
    }

    private func sendText(_ text: String, to surface: ghostty_surface_t) {
        text.withCString { ptr in
            ghostty_surface_text(surface, ptr, UInt(text.utf8.count))
        }
    }

    private func committedText(from string: Any) -> String? {
        if let attributed = string as? NSAttributedString {
            return attributed.string
        }
        return string as? String
    }

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self,
                  event.window === self.window,
                  self.surface != nil,
                  self.hasTerminalFocus,
                  self.wantsTerminalKeyEvents else {
                return event
            }
            guard !self.hasMarkedText() else { return event }
            return self.sendControlSequence(for: event) ? nil : event
        }
    }

    private var hasTerminalFocus: Bool {
        window?.firstResponder === self
    }

    private func removeKeyMonitor() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
    }

    func hasMarkedText() -> Bool {
        markedText.length > 0
    }

    func markedRange() -> NSRange {
        markedText.length > 0 ? NSRange(location: 0, length: markedText.length) : NSRange(location: NSNotFound, length: 0)
    }

    func selectedRange() -> NSRange {
        markedSelectedRange
    }

    func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        let text: String
        if let attributed = string as? NSAttributedString {
            text = attributed.string
            markedText = NSMutableAttributedString(attributedString: attributed)
        } else if let plainText = string as? String {
            text = plainText
            markedText = NSMutableAttributedString(string: plainText)
        } else {
            return
        }
        markedSelectedRange = selectedRange

        guard let surface else { return }
        if text.isEmpty {
            ghostty_surface_preedit(surface, nil, 0)
        } else {
            text.withCString { ptr in
                ghostty_surface_preedit(surface, ptr, UInt(text.utf8.count))
            }
        }
    }

    func unmarkText() {
        markedText = NSMutableAttributedString()
        markedSelectedRange = NSRange(location: NSNotFound, length: 0)
        if let surface {
            ghostty_surface_preedit(surface, nil, 0)
        }
    }

    func validAttributesForMarkedText() -> [NSAttributedString.Key] {
        []
    }

    func attributedSubstring(forProposedRange range: NSRange, actualRange: NSRangePointer?) -> NSAttributedString? {
        nil
    }

    func characterIndex(for point: NSPoint) -> Int {
        0
    }

    func firstRect(forCharacterRange range: NSRange, actualRange: NSRangePointer?) -> NSRect {
        guard let window else { return .zero }
        actualRange?.pointee = range

        let rectInView: NSRect
        if let surface {
            var x: Double = 0
            var y: Double = 0
            var width: Double = max(Double(cellSize.width), 1)
            var height: Double = max(Double(cellSize.height), 1)
            ghostty_surface_ime_point(surface, &x, &y, &width, &height)
            rectInView = NSRect(
                x: x,
                y: bounds.height - CGFloat(y),
                width: max(CGFloat(width), 1),
                height: max(CGFloat(height), cellSize.height, 1)
            )
        } else {
            rectInView = NSRect(x: bounds.minX, y: bounds.minY, width: 1, height: max(cellSize.height, 1))
        }

        return window.convertToScreen(convert(rectInView, to: nil))
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        scheduleSurfaceResize(for: newSize)
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        scheduleSurfaceResize(for: bounds.size)
    }

    private func scheduleSurfaceResize(for size: NSSize) {
        guard surface != nil else { return }
        guard let pixelSize = pixelSize(for: size, scale: window?.backingScaleFactor ?? 2.0) else { return }
        guard pixelSize != appliedSurfaceSize,
              pixelSize != pendingSurfaceSize else { return }

        pendingSurfaceSize = pixelSize
        guard resizeWorkItem == nil else { return }

        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.resizeWorkItem = nil
            guard let surface = self.surface,
                  let pending = self.pendingSurfaceSize else { return }
            self.pendingSurfaceSize = nil
            self.applySurfaceSizeNow(pending, to: surface)
        }
        resizeWorkItem = item
        DispatchQueue.main.async(execute: item)
    }

    private func applySurfaceSizeNow(_ size: SurfacePixelSize?, to surface: ghostty_surface_t) {
        guard let size, size != appliedSurfaceSize else { return }
        ghostty_surface_set_size(surface, size.width, size.height)
        appliedSurfaceSize = size
    }

    private func pixelSize(for size: NSSize, scale: CGFloat) -> SurfacePixelSize? {
        let width = UInt32(size.width * scale)
        let height = UInt32(size.height * scale)
        guard width > 0 && height > 0 else { return nil }
        return SurfacePixelSize(width: width, height: height)
    }

    /// Reject a working-directory hint that doesn't point at an existing
    /// directory. libghostty's `ghostty_surface_new` SIGSEGVs when handed
    /// a missing path and silently ignores a path that exists but is a
    /// regular file; centralizing the validation here means every spawn
    /// site stays safe.
    static func validatedDirectory(_ path: String?) -> String? {
        guard let path else { return nil }
        var isDir: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: path, isDirectory: &isDir)
        return (exists && isDir.boolValue) ? path : nil
    }
}

private struct WeakTerminalView {
    weak var view: GhosttyTerminalView?

    init(_ view: GhosttyTerminalView) {
        self.view = view
    }
}
