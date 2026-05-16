import Foundation

/// A workspace owns a list of tabs. Each tab holds a binary split tree of
/// terminals. Surfaces themselves are not stored — only the structural ids.
struct Workspace: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var tabs: [TerminalTab]
    var selectedTabId: UUID?
    /// Optional shell command executed in newly created terminals inside
    /// this workspace (when no Quick Action or resume command takes
    /// precedence). Typical use: pin a workspace to its project directory's
    /// dev server launcher.
    var defaultCommand: String?

    init(id: UUID = UUID(), name: String, tabs: [TerminalTab] = [], defaultCommand: String? = nil) {
        self.id = id
        self.name = name
        self.tabs = tabs
        self.selectedTabId = tabs.first?.id
        self.defaultCommand = defaultCommand
    }
}

/// What flavor of tab this is. `.shell` is the default — a plain
/// interactive terminal. `.git` is the dedicated git-viewer slot
/// (lazygit / gitui / …) that the user pins per workspace.
enum TabKind: String, Codable, Equatable {
    case shell
    case git
}

struct TerminalTab: Codable, Identifiable, Equatable {
    var id: UUID
    var title: String
    var layout: SplitNode
    var focusedTerminalId: UUID
    /// Set when this tab was spawned from a Quick Action click. Used by
    /// `StartupCommandResolver` so the first terminal in the tab inherits
    /// the action's command (or resume override) instead of the workspace
    /// default. nil for plain "shell" tabs.
    var quickActionId: QuickActionId?
    /// Tab flavor. Defaults to `.shell` so existing persisted tabs
    /// continue to decode without a migration.
    var kind: TabKind

    init(
        id: UUID = UUID(),
        title: String,
        quickActionId: QuickActionId? = nil,
        kind: TabKind = .shell
    ) {
        self.id = id
        self.title = title
        let leaf = UUID()
        self.layout = .terminal(leaf)
        self.focusedTerminalId = leaf
        self.quickActionId = quickActionId
        self.kind = kind
    }

    // Backwards-compat: tabs persisted before TabKind was introduced
    // don't carry the field. Default-decode to `.shell` so old
    // workspaces still load.
    enum CodingKeys: String, CodingKey {
        case id, title, layout, focusedTerminalId, quickActionId, kind
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(UUID.self, forKey: .id)
        self.title = try c.decode(String.self, forKey: .title)
        self.layout = try c.decode(SplitNode.self, forKey: .layout)
        self.focusedTerminalId = try c.decode(UUID.self, forKey: .focusedTerminalId)
        self.quickActionId = try c.decodeIfPresent(QuickActionId.self, forKey: .quickActionId)
        self.kind = try c.decodeIfPresent(TabKind.self, forKey: .kind) ?? .shell
    }
}

enum SplitDirection: String, Codable, Equatable {
    case horizontal  // panes stacked vertically (separator is horizontal)
    case vertical    // panes side by side (separator is vertical)
}

/// Compass direction for keyboard pane-focus navigation.
enum FocusDirection {
    case left, right, up, down
}

/// Binary tree of splits with terminal-id leaves. The terminal id is the
/// stable handle used to look up the actual ghostty surface at runtime;
/// surfaces themselves are never serialized.
indirect enum SplitNode: Codable, Equatable {
    case terminal(UUID)
    case split(id: UUID, direction: SplitDirection, firstRatio: Double, first: SplitNode, second: SplitNode)

    func allTerminalIds() -> [UUID] {
        switch self {
        case .terminal(let id):
            return [id]
        case .split(_, _, _, let a, let b):
            return a.allTerminalIds() + b.allTerminalIds()
        }
    }

    /// Replace the leaf with `terminalId` by `replacement`. Returns a new
    /// tree; non-matching subtrees are returned unchanged.
    func replacing(terminalId: UUID, with replacement: SplitNode) -> SplitNode {
        switch self {
        case .terminal(let id):
            return id == terminalId ? replacement : self
        case .split(let sid, let dir, let r, let a, let b):
            return .split(
                id: sid, direction: dir, firstRatio: r,
                first: a.replacing(terminalId: terminalId, with: replacement),
                second: b.replacing(terminalId: terminalId, with: replacement)
            )
        }
    }

    /// Remove the leaf with `terminalId`; collapses single-child splits.
    /// Returns nil if removing the leaf empties the tree entirely.
    func removing(terminalId: UUID) -> SplitNode? {
        switch self {
        case .terminal(let id):
            return id == terminalId ? nil : self
        case .split(let sid, let dir, let r, let a, let b):
            let na = a.removing(terminalId: terminalId)
            let nb = b.removing(terminalId: terminalId)
            switch (na, nb) {
            case (nil, nil): return nil
            case (nil, let only?): return only
            case (let only?, nil): return only
            case (let aa?, let bb?):
                return .split(id: sid, direction: dir, firstRatio: r, first: aa, second: bb)
            }
        }
    }

    /// Update the firstRatio of the split node identified by `splitId`.
    func updatingRatio(splitId: UUID, to newRatio: Double) -> SplitNode {
        switch self {
        case .terminal:
            return self
        case .split(let sid, let dir, _, let a, let b) where sid == splitId:
            return .split(id: sid, direction: dir, firstRatio: newRatio.clamped(0.05, 0.95), first: a, second: b)
        case .split(let sid, let dir, let r, let a, let b):
            return .split(
                id: sid, direction: dir, firstRatio: r,
                first: a.updatingRatio(splitId: splitId, to: newRatio),
                second: b.updatingRatio(splitId: splitId, to: newRatio)
            )
        }
    }

    /// Walks from the focused leaf toward the root and returns the next
    /// terminal id in the requested direction, or nil if there is no neighbor
    /// (focused pane is on the edge of the tab).
    func neighbor(of terminalId: UUID, direction: FocusDirection) -> UUID? {
        let wantedSplit: SplitDirection = (direction == .left || direction == .right) ? .vertical : .horizontal
        // Forward branch: when moving right/down we expect to be in the "first"
        // child of the matching ancestor; when moving left/up, the "second".
        let mustBeFirst = (direction == .right || direction == .down)
        var path: [SplitNode] = []
        guard collectPath(to: terminalId, into: &path) else { return nil }
        // path is [root, ..., leaf]. Walk from leaf upward.
        var child: SplitNode = .terminal(terminalId)
        for ancestor in path.reversed().dropFirst() {
            guard case .split(_, let dir, _, let a, let b) = ancestor else { continue }
            let cameFromFirst = isSame(a, child)
            if dir == wantedSplit && cameFromFirst == mustBeFirst {
                let sibling = cameFromFirst ? b : a
                return sibling.descendNearest(toward: direction)
            }
            child = ancestor
        }
        return nil
    }

    /// Pick the leaf in this subtree closest to the boundary we just crossed.
    private func descendNearest(toward direction: FocusDirection) -> UUID {
        switch self {
        case .terminal(let id): return id
        case .split(_, let dir, _, let a, let b):
            let pickFirst: Bool
            switch (direction, dir) {
            case (.right, .vertical): pickFirst = true   // leftmost
            case (.left, .vertical):  pickFirst = false  // rightmost
            case (.down, .horizontal): pickFirst = true  // topmost
            case (.up, .horizontal):   pickFirst = false // bottommost
            default: pickFirst = true                    // orthogonal — arbitrary
            }
            return (pickFirst ? a : b).descendNearest(toward: direction)
        }
    }

    /// Build the path from root to the leaf with `terminalId`.
    private func collectPath(to terminalId: UUID, into path: inout [SplitNode]) -> Bool {
        path.append(self)
        switch self {
        case .terminal(let id):
            if id == terminalId { return true }
            path.removeLast()
            return false
        case .split(_, _, _, let a, let b):
            if a.collectPath(to: terminalId, into: &path) { return true }
            if b.collectPath(to: terminalId, into: &path) { return true }
            path.removeLast()
            return false
        }
    }

    private func isSame(_ lhs: SplitNode, _ rhs: SplitNode) -> Bool {
        switch (lhs, rhs) {
        case (.terminal(let a), .terminal(let b)): return a == b
        case (.split(let a, _, _, _, _), .split(let b, _, _, _, _)): return a == b
        default: return false
        }
    }

    /// Tree is "structurally equal" if it has the same shape and same
    /// terminal ids — split ratios may differ. Used to skip view rebuilds
    /// when only divider position changed.
    func sameStructure(as other: SplitNode) -> Bool {
        switch (self, other) {
        case (.terminal(let a), .terminal(let b)): return a == b
        case (.split(let aid, let adir, _, let a1, let a2),
              .split(let bid, let bdir, _, let b1, let b2)):
            return aid == bid && adir == bdir && a1.sameStructure(as: b1) && a2.sameStructure(as: b2)
        default: return false
        }
    }
}

private extension Double {
    func clamped(_ lo: Double, _ hi: Double) -> Double { min(max(self, lo), hi) }
}
