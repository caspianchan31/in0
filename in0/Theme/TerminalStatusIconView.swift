import AppKit
import QuartzCore

/// 10×10 dot / spinning arc that paints one of in0's six terminal-status
/// kinds. Mutates only through `update(status:theme:)` — callers hand it
/// the latest state and the view picks which CALayer paths / animations
/// to show. Doing this with CALayer (rather than SwiftUI's `Canvas`) keeps
/// the rotation animation smooth and lets us share the view from both
/// SwiftUI (via NSViewRepresentable) and AppKit (sidebar list rows).
final class TerminalStatusIconView: NSView {

    static let size: CGFloat = 10

    private var status: TerminalStatus = .neverRan
    private var theme: AppTheme = .darkDefault

    private let shapeLayer = CAShapeLayer()

    override init(frame: NSRect) {
        super.init(frame: NSRect(x: 0, y: 0, width: Self.size, height: Self.size))
        wantsLayer = true
        layer?.addSublayer(shapeLayer)
        shapeLayer.frame = bounds
        render()
    }
    required init?(coder: NSCoder) { fatalError("not supported") }

    override func layout() {
        super.layout()
        shapeLayer.frame = bounds
        render()
    }

    func update(status: TerminalStatus, theme: AppTheme) {
        let kindChanged = !Self.sameKind(status, self.status)
        self.status = status
        self.theme = theme
        render()
        if kindChanged {
            stopSpin()
            if case .running = status { startSpin() }
        }
        toolTip = Self.tooltip(for: status)
    }

    /// Compares only the case, ignoring associated values. Used to decide
    /// whether the spin animation should restart — a `running` → `running`
    /// transition (tool detail changed, same turn) shouldn't blow away the
    /// rotation midway.
    private static func sameKind(_ a: TerminalStatus, _ b: TerminalStatus) -> Bool {
        switch (a, b) {
        case (.neverRan, .neverRan),
             (.running, .running),
             (.idle, .idle),
             (.needsInput, .needsInput),
             (.success, .success),
             (.failed, .failed):
            return true
        default:
            return false
        }
    }

    /// Style record used by `render()` for non-running kinds. Returns nil
    /// for `running` — that kind paints a custom 270° arc, not an ellipse.
    static func renderStyle(for status: TerminalStatus, theme: AppTheme)
        -> (fill: NSColor, stroke: NSColor, lineWidth: CGFloat)?
    {
        switch status {
        case .neverRan:
            return (NSColor.clear, theme.textTertiaryNS, 1)
        case .running:
            return nil
        case .idle:
            return (NSColor.clear, theme.textTertiaryNS.withAlphaComponent(0.6), 1)
        case .needsInput:
            return (theme.accentNS, NSColor.clear, 0)
        case .success(_, _, _, _, _, let readAt):
            return readAt == nil
                ? (theme.successNS, NSColor.clear, 0)
                : (NSColor.clear, theme.textTertiaryNS, 1)
        case .failed(_, _, _, _, _, let readAt):
            return readAt == nil
                ? (theme.dangerNS, NSColor.clear, 0)
                : (NSColor.clear, theme.textTertiaryNS, 1)
        }
    }

    private func render() {
        let rect = bounds.insetBy(dx: 1, dy: 1)
        if case .running = status {
            let center = CGPoint(x: rect.midX, y: rect.midY)
            let radius = min(rect.width, rect.height) / 2
            let path = CGMutablePath()
            // 270° open arc — visible gap reads as "spinning ring".
            path.addArc(center: center, radius: radius,
                        startAngle: 0, endAngle: CGFloat.pi * 1.5,
                        clockwise: false)
            shapeLayer.path = path
            shapeLayer.fillColor = NSColor.clear.cgColor
            shapeLayer.strokeColor = theme.accentNS.cgColor
            shapeLayer.lineWidth = 1.5
            shapeLayer.lineCap = .round
            return
        }
        guard let style = Self.renderStyle(for: status, theme: theme) else { return }
        shapeLayer.path = CGPath(ellipseIn: rect, transform: nil)
        shapeLayer.fillColor = style.fill.cgColor
        shapeLayer.strokeColor = style.stroke.cgColor
        shapeLayer.lineWidth = style.lineWidth
    }

    private func startSpin() {
        guard shapeLayer.animation(forKey: "spin") == nil else { return }
        shapeLayer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        shapeLayer.position = CGPoint(x: bounds.midX, y: bounds.midY)
        shapeLayer.bounds = bounds
        let spin = CABasicAnimation(keyPath: "transform.rotation.z")
        spin.fromValue = 0
        spin.toValue = -CGFloat.pi * 2   // clockwise
        spin.duration = 1.0
        spin.repeatCount = .infinity
        spin.isRemovedOnCompletion = false
        shapeLayer.add(spin, forKey: "spin")
    }

    private func stopSpin() {
        shapeLayer.removeAnimation(forKey: "spin")
        shapeLayer.transform = CATransform3DIdentity
    }

    static func tooltip(for status: TerminalStatus) -> String? {
        switch status {
        case .neverRan:
            return nil
        case .running(let startedAt, let detail):
            let elapsed = max(0, Date().timeIntervalSince(startedAt))
            let head = "Running for \(format(elapsed))"
            return detail.map { "\(head)\n\($0)" } ?? head
        case .idle(let since):
            let elapsed = max(0, Date().timeIntervalSince(since))
            return "Idle for \(format(elapsed))"
        case .needsInput(let since):
            let elapsed = max(0, Date().timeIntervalSince(since))
            return "Needs input (\(format(elapsed)) ago)"
        case .success(_, let duration, _, let agent, let summary, let readAt):
            let head = "\(agent.displayName): turn finished · \(format(duration))"
            let prefix = readAt != nil ? "\(head) · read" : head
            return summary.map { "\(prefix)\n\($0)" } ?? prefix
        case .failed(_, let duration, _, let agent, let summary, let readAt):
            let head = "\(agent.displayName): turn had tool errors · \(format(duration))"
            let prefix = readAt != nil ? "\(head) · read" : head
            return summary.map { "\(prefix)\n\($0)" } ?? prefix
        }
    }

    private static func format(_ seconds: TimeInterval) -> String {
        if seconds < 1 { return "<1s" }
        if seconds < 60 { return "\(Int(seconds))s" }
        let m = Int(seconds) / 60
        let s = Int(seconds) % 60
        return s == 0 ? "\(m)m" : "\(m)m\(s)s"
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: Self.size, height: Self.size)
    }
}
