import SwiftUI

struct AIHistoryPluginCardView: View {
    @Environment(ThemeManager.self) private var theme
    @Environment(AIHistoryStore.self) private var histories
    @Environment(TodoStore.self) private var todos
    @Environment(WorkspaceStore.self) private var workspaces

    let workspace: Workspace

    var body: some View {
        let t = theme.currentTheme
        let result = histories.result(for: workspace.id)
        let isRunning = histories.runningWorkspaceIds.contains(workspace.id)
        let entries = result?.entries ?? []

        PluginCardContainer(title: "AI History", trailing: isRunning ? "scanning" : trailing(entries)) {
            VStack(alignment: .leading, spacing: DT.Space.sm) {
                if let error = result?.error, entries.isEmpty {
                    Text(error)
                        .font(.system(size: 11))
                        .foregroundStyle(t.textSecondary)
                        .lineLimit(3)
                } else if entries.isEmpty {
                    Text("Scan this workspace for local AI conversation files.")
                        .font(.system(size: 11))
                        .foregroundStyle(t.textSecondary)
                } else {
                    ForEach(entries.prefix(3)) { entry in
                        entryRow(entry, theme: t)
                    }
                }

                HStack(spacing: DT.Space.sm) {
                    Button(isRunning ? "Scanning..." : "Refresh") {
                        histories.scan(workspace: workspace)
                    }
                    .buttonStyle(.borderless)
                    .disabled(isRunning)

                    Button("Create Todo") {
                        _ = todos.add(
                            title: "Review AI history for \(workspace.name)",
                            workspaceId: workspace.id,
                            source: .aiHistory,
                            note: entries.first?.snippet ?? result?.error ?? ""
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(entries.isEmpty)
                }
                .font(.system(size: 10, weight: .medium))
            }
        }
    }

    private func entryRow(_ entry: AIHistoryEntry, theme: AppTheme) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: DT.Space.xs) {
                Text(entry.agent)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(theme.accent)
                Text(entry.title)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(theme.textPrimary)
                    .lineLimit(1)
            }
            Text(entry.snippet)
                .font(.system(size: 10))
                .foregroundStyle(theme.textSecondary)
                .lineLimit(2)
            Text(entry.relativePath)
                .font(.system(size: 9))
                .foregroundStyle(theme.textTertiary)
                .lineLimit(1)
            if let command = entry.resumeCommand {
                Button("Resume") {
                    _ = workspaces.launchCommandInNewTab(
                        workspaceId: workspace.id,
                        title: "\(entry.agent) resume",
                        command: command
                    )
                }
                .buttonStyle(.plain)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(theme.accent)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func trailing(_ entries: [AIHistoryEntry]) -> String? {
        entries.isEmpty ? nil : "\(entries.count) found"
    }
}
