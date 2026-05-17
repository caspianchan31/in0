import Foundation

typealias PluginId = String

/// Broad plugin families. The first version ships only built-in plugins,
/// but the model keeps the catalog independent from Quick Actions so later
/// releases can add panels, background scans, and external manifests.
enum PluginKind: String, Codable, CaseIterable {
    case task
    case scanner

    var label: String {
        switch self {
        case .task: return "Task"
        case .scanner: return "Scanner"
        }
    }
}

enum PluginSurface: String, Codable, CaseIterable {
    case workspaceCard
    case cardDetail
    case quickAction
    case externalWindow

    var label: String {
        switch self {
        case .workspaceCard: return "Workspace Card"
        case .cardDetail: return "Card Detail"
        case .quickAction: return "Quick Action"
        case .externalWindow: return "External Window"
        }
    }
}

typealias PluginCardId = String

struct PluginCardSurface: Equatable, Identifiable {
    let id: PluginCardId
    var title: String
    var summary: String
    var icon: QuickActionIcon
    var supportsDetail: Bool
}

struct PluginQuickAction: Equatable, Identifiable {
    let id: QuickActionId
    var title: String
    var command: String
    var icon: QuickActionIcon
}

struct PluginDefinition: Identifiable, Equatable {
    let id: PluginId
    var title: String
    var summary: String
    var kind: PluginKind
    var surfaces: Set<PluginSurface>
    var cards: [PluginCardSurface]
    var quickActions: [PluginQuickAction]
}

enum BuiltinPlugin: String, CaseIterable {
    case todoList = "todo-list"
    case githubScan = "github-scan"
    case agentStatus = "agent-status"
    case aiHistory = "ai-history"

    var definition: PluginDefinition {
        switch self {
        case .todoList:
            return PluginDefinition(
                id: rawValue,
                title: "Todo List",
                summary: "Track workspace tasks in the right-side plugin cards.",
                kind: .task,
                surfaces: [.workspaceCard, .cardDetail, .quickAction],
                cards: [
                    PluginCardSurface(
                        id: "todo",
                        title: "Todo",
                        summary: "Capture and complete tasks for this workspace.",
                        icon: .sfSymbol("checklist"),
                        supportsDetail: true
                    )
                ],
                quickActions: [
                    PluginQuickAction(
                        id: "plugin.todo-list.open",
                        title: "Todo",
                        command: "printf '\\n# in0 Todo List\\n- [ ] Capture the next task\\n' && ${EDITOR:-nano} .in0-todo.md",
                        icon: .sfSymbol("checklist")
                    )
                ]
            )
        case .githubScan:
            return PluginDefinition(
                id: rawValue,
                title: "GitHub Scan",
                summary: "Run a lightweight repository scan for remotes, status, and recent commits.",
                kind: .scanner,
                surfaces: [.workspaceCard, .cardDetail, .quickAction],
                cards: [
                    PluginCardSurface(
                        id: "github-scan",
                        title: "GitHub Scan",
                        summary: "Inspect local repository status for this workspace.",
                        icon: .sfSymbol("dot.viewfinder"),
                        supportsDetail: true
                    )
                ],
                quickActions: [
                    PluginQuickAction(
                        id: "plugin.github-scan.run",
                        title: "GitHub Scan",
                        command: "git remote -v && printf '\\n--- status ---\\n' && git status --short --branch && printf '\\n--- recent commits ---\\n' && git log --oneline -8",
                        icon: .sfSymbol("magnifyingglass.circle")
                    )
                ]
            )
        case .agentStatus:
            return PluginDefinition(
                id: rawValue,
                title: "Agent Status",
                summary: "Show current agent hook status for the active workspace.",
                kind: .scanner,
                surfaces: [.workspaceCard, .cardDetail],
                cards: [
                    PluginCardSurface(
                        id: "agent-status",
                        title: "Agent Status",
                        summary: "Monitor Codex, Claude Code, and OpenCode status.",
                        icon: .sfSymbol("sparkles"),
                        supportsDetail: true
                    )
                ],
                quickActions: []
            )
        case .aiHistory:
            return PluginDefinition(
                id: rawValue,
                title: "AI History",
                summary: "Read local AI conversation history files from the workspace folder.",
                kind: .scanner,
                surfaces: [.workspaceCard, .cardDetail, .quickAction],
                cards: [
                    PluginCardSurface(
                        id: "ai-history",
                        title: "AI History",
                        summary: "Inspect recent Claude, Codex, and OpenCode history in this workspace.",
                        icon: .sfSymbol("clock.arrow.circlepath"),
                        supportsDetail: true
                    )
                ],
                quickActions: [
                    PluginQuickAction(
                        id: "plugin.ai-history.list",
                        title: "AI History",
                        command: "find . \\( -path './.git' -o -path './node_modules' -o -path './vendor' \\) -prune -o -type f \\( -path './.claude/*' -o -path './.codex/*' -o -path './.opencode/*' -o -path './.in0/ai-history/*' -o -iname '*history*' -o -iname '*conversation*' -o -iname '*transcript*' \\) -print | head -40",
                        icon: .sfSymbol("clock.arrow.circlepath")
                    )
                ]
            )
        }
    }
}

enum PluginCatalog {
    static let definitions: [PluginDefinition] = BuiltinPlugin.allCases.map(\.definition)

    static func definition(id: PluginId) -> PluginDefinition? {
        definitions.first { $0.id == id }
    }

    static func action(id: QuickActionId) -> (plugin: PluginDefinition, action: PluginQuickAction)? {
        for plugin in definitions {
            if let action = plugin.quickActions.first(where: { $0.id == id }) {
                return (plugin, action)
            }
        }
        return nil
    }

    static var actionIds: [QuickActionId] {
        definitions.flatMap { $0.quickActions.map(\.id) }
    }

    static var cardIds: [PluginCardId] {
        definitions.flatMap { $0.cards.map(\.id) }
    }

    static func card(id: PluginCardId) -> (plugin: PluginDefinition, card: PluginCardSurface)? {
        for plugin in definitions {
            if let card = plugin.cards.first(where: { $0.id == id }) {
                return (plugin, card)
            }
        }
        return nil
    }
}
