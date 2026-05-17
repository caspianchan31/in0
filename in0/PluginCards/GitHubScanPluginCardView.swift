import SwiftUI

struct GitHubScanPluginCardView: View {
    @Environment(ThemeManager.self) private var theme
    @Environment(GitHubScanStore.self) private var scans
    @Environment(TodoStore.self) private var todos

    let workspace: Workspace

    var body: some View {
        let t = theme.currentTheme
        let result = scans.result(for: workspace.id)
        let isRunning = scans.runningWorkspaceIds.contains(workspace.id)

        PluginCardContainer(title: "GitHub Scan", trailing: isRunning ? "running" : nil) {
            VStack(alignment: .leading, spacing: DT.Space.sm) {
                if let error = result?.error {
                    Text(error)
                        .font(.system(size: 11))
                        .foregroundStyle(t.danger)
                } else {
                    infoRow("branch", result?.branch ?? "-")
                    infoRow("remote", shortRemote(result?.remote ?? "-"))
                    infoRow("status", result?.statusSummary ?? "not scanned")
                    if let checks = result?.checks, !checks.isEmpty {
                        VStack(alignment: .leading, spacing: 3) {
                            ForEach(checks.prefix(3), id: \.self) { check in
                                HStack(spacing: DT.Space.xs) {
                                    Image(systemName: check.hasPrefix("Untracked") || check.hasPrefix("Modified") ? "exclamationmark.circle" : "checkmark.circle")
                                        .font(.system(size: 10))
                                        .foregroundStyle(check.hasPrefix("Untracked") || check.hasPrefix("Modified") ? t.warning : t.success)
                                    Text(check)
                                        .font(.system(size: 10))
                                        .foregroundStyle(t.textSecondary)
                                        .lineLimit(1)
                                }
                            }
                        }
                    }
                }

                HStack(spacing: DT.Space.sm) {
                    Button(isRunning ? "Scanning..." : "Run Scan") {
                        scans.scan(workspace: workspace)
                    }
                    .buttonStyle(.borderless)
                    .disabled(isRunning)
                    Button("Create Todo") {
                        _ = todos.add(
                            title: "Review GitHub Scan for \(workspace.name)",
                            workspaceId: workspace.id,
                            source: .gitHubScan,
                            note: result?.statusSummary ?? ""
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(result == nil)
                }
                .font(.system(size: 10, weight: .medium))
            }
        }
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: DT.Space.sm) {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(theme.currentTheme.textTertiary)
                .frame(width: 44, alignment: .leading)
            Text(value)
                .font(.system(size: 10))
                .foregroundStyle(theme.currentTheme.textPrimary)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
    }

    private func shortRemote(_ remote: String) -> String {
        remote.split(separator: "\t").first.map(String.init) ?? remote
    }
}
