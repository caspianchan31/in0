import SwiftUI

struct AgentStatusPluginCardView: View {
    @Environment(ThemeManager.self) private var theme
    @Environment(TerminalStatusStore.self) private var statuses
    @Environment(TodoStore.self) private var todos

    let workspace: Workspace

    var body: some View {
        let t = theme.currentTheme
        let terminals = workspace.tabs.flatMap { $0.layout.allTerminalIds() }
        let aggregate = statuses.aggregate(over: terminals)

        PluginCardContainer(title: "Agent Status", trailing: aggregate.caseName) {
            VStack(alignment: .leading, spacing: DT.Space.sm) {
                ForEach(HookAgent.allCases, id: \.rawValue) { agent in
                    agentRow(agent, in: terminals)
                }
                HStack {
                    Text(summary(for: aggregate))
                        .font(.system(size: 10))
                        .foregroundStyle(t.textTertiary)
                        .lineLimit(1)
                    Spacer()
                    Button("Add to Todo") {
                        _ = todos.add(
                            title: "Review agent status: \(aggregate.caseName)",
                            workspaceId: workspace.id,
                            source: .agentStatus
                        )
                    }
                    .font(.system(size: 10, weight: .medium))
                    .buttonStyle(.plain)
                    .disabled(aggregate == .neverRan)
                }
            }
        }
    }

    private func agentRow(_ agent: HookAgent, in terminals: [UUID]) -> some View {
        let terminal = terminals.first { statuses.agents[$0] == agent }
        let status = terminal.map { statuses.status(for: $0) } ?? .neverRan
        return HStack(spacing: DT.Space.xs) {
            Circle()
                .fill(color(for: status))
                .frame(width: 7, height: 7)
            Text(agent.displayName)
                .font(.system(size: 11))
                .foregroundStyle(theme.currentTheme.textPrimary)
            Spacer()
            Text(status.caseName)
                .font(.system(size: 10))
                .foregroundStyle(theme.currentTheme.textTertiary)
        }
    }

    private func color(for status: TerminalStatus) -> Color {
        let t = theme.currentTheme
        switch status {
        case .running: return t.accent
        case .needsInput: return t.warning
        case .success: return t.success
        case .failed: return t.danger
        case .idle: return t.textTertiary
        case .neverRan: return t.border
        }
    }

    private func summary(for status: TerminalStatus) -> String {
        switch status {
        case .neverRan: return "No agent events yet"
        case .running: return "Agent running"
        case .idle: return "Agent idle"
        case .needsInput: return "Agent needs input"
        case .success: return "Last event succeeded"
        case .failed: return "Last event failed"
        }
    }
}
