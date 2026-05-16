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
    private var keyMonitor: Any?
    private var wantsTerminalKeyEvents = false

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
            let w = UInt32(bounds.width * scale)
            let h = UInt32(bounds.height * scale)
            if w > 0 && h > 0 {
                ghostty_surface_set_size(surface, w, h)
            }
            window.makeFirstResponder(self)
            wantsTerminalKeyEvents = true
            // Drain any startup command enqueued by WorkspaceStore's
            // `startupCommandPolicy` — that hook runs the resolver at tab
            // creation time and writes its result into the queue, so the
            // surface only has to play it back.
            if let cmd = TerminalCommandQueue.shared.drain(for: terminalId) {
                let toSend = cmd.hasSuffix("\n") ? cmd : cmd + "\r"
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                    guard let self, let surface = self.surface else { return }
                    self.sendText(toSend, to: surface)
                }
            }
        }
    }

    /// Called by the cache owner when the terminal is closed for good.
    func dispose() {
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
        wantsTerminalKeyEvents = true
        focusTerminal()
        super.mouseDown(with: event)
    }

    override func keyDown(with event: NSEvent) {
        guard surface != nil else {
            super.keyDown(with: event)
            return
        }
        if sendControlSequence(for: event) {
            return
        }
        interpretKeyEvents([event])
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.command),
           event.charactersIgnoringModifiers?.lowercased() == "v" {
            paste(nil)
            return true
        }
        return super.performKeyEquivalent(with: event)
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
        guard let surface, let text = committedText(from: string), !text.isEmpty else { return }
        unmarkText()
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

    private func sendKey(_ event: NSEvent, text: UnsafePointer<CChar>?, to surface: ghostty_surface_t) {
        let input = ghostty_input_key_s(
            action: GHOSTTY_ACTION_PRESS,
            mods: inputMods(from: event),
            consumed_mods: GHOSTTY_MODS_NONE,
            keycode: UInt32(event.keyCode),
            text: text,
            unshifted_codepoint: 0,
            composing: false
        )
        _ = ghostty_surface_key(surface, input)
    }

    private func inputMods(from event: NSEvent) -> ghostty_input_mods_e {
        var mods = GHOSTTY_MODS_NONE
        if event.modifierFlags.contains(.shift) {
            mods = ghostty_input_mods_e(rawValue: mods.rawValue | GHOSTTY_MODS_SHIFT.rawValue)
        }
        if event.modifierFlags.contains(.control) {
            mods = ghostty_input_mods_e(rawValue: mods.rawValue | GHOSTTY_MODS_CTRL.rawValue)
        }
        if event.modifierFlags.contains(.option) {
            mods = ghostty_input_mods_e(rawValue: mods.rawValue | GHOSTTY_MODS_ALT.rawValue)
        }
        if event.modifierFlags.contains(.command) {
            mods = ghostty_input_mods_e(rawValue: mods.rawValue | GHOSTTY_MODS_SUPER.rawValue)
        }
        if event.modifierFlags.contains(.capsLock) {
            mods = ghostty_input_mods_e(rawValue: mods.rawValue | GHOSTTY_MODS_CAPS.rawValue)
        }
        return mods
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
                  self.wantsTerminalKeyEvents else {
                return event
            }
            return self.sendControlSequence(for: event) ? nil : event
        }
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
        NSRange(location: NSNotFound, length: 0)
    }

    func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        if let attributed = string as? NSAttributedString {
            markedText = NSMutableAttributedString(attributedString: attributed)
        } else if let text = string as? String {
            markedText = NSMutableAttributedString(string: text)
        }
    }

    func unmarkText() {
        markedText = NSMutableAttributedString()
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
        return window.convertToScreen(convert(bounds, to: nil))
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        guard let surface else { return }
        let scale = window?.backingScaleFactor ?? 2.0
        let w = UInt32(newSize.width * scale)
        let h = UInt32(newSize.height * scale)
        if w > 0 && h > 0 {
            ghostty_surface_set_size(surface, w, h)
        }
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
