import SwiftUI

/// Sidebar shell. Header + workspace list + footer chrome live here, but
/// the list itself is `SidebarListBridge` wrapping the AppKit
/// `WorkspaceListView` — that's where drag-reorder, inline rename, and
/// the right-click menu live. Pure-SwiftUI would force us to fight
/// SwiftUI's drag/drop primitives every time AppKit changes its
/// pasteboard or first-responder rules.
struct SidebarView: View {
    @Environment(ThemeManager.self) private var theme
    @Environment(WorkspaceStore.self) private var store
    @Environment(WorkspaceMetadataStore.self) private var metadata
    @Environment(TerminalStatusStore.self) private var statuses
    @Environment(LanguageStore.self) private var language
    @Environment(SettingsStore.self) private var settings
    @Environment(UpdateStore.self) private var updateStore

    @State private var metadataTick = 0
    @State private var deleteCandidate: UUID?
    @State private var commandEditTarget: UUID?
    @State private var commandEditValue: String = ""

    var body: some View {
        let t = theme.currentTheme
        let bgOpacity = theme.backgroundOpacity
        VStack(alignment: .leading, spacing: 0) {
            header(t: t)
            SidebarListBridge(
                store: store,
                statusStore: statuses,
                theme: t,
                metadata: metadataDictionary,
                metadataTick: metadataTick,
                languageTick: language.tick,
                backgroundOpacity: bgOpacity,
                showStatusIndicators: settings.snapshot.statusIndicatorsEnabled
                    && StatusIndicatorGate.anyAgentEnabled(settings.configStore),
                onRequestDelete: { id in deleteCandidate = id },
                onRequestEditCommand: { id, current in
                    commandEditTarget = id
                    commandEditValue = current
                }
            )
            .background(t.sidebar.opacity(bgOpacity))
            Spacer(minLength: 0)
            displayTitle(t: t)
            footer(t: t)
        }
        .padding(.leading, DT.Layout.sidebarContentLeadingInset)
        .onChange(of: metadata.snapshots) { _, _ in metadataTick &+= 1 }
        .alert(
            "Delete workspace?",
            isPresented: Binding(
                get: { deleteCandidate != nil },
                set: { if !$0 { deleteCandidate = nil } }
            ),
            presenting: deleteCandidate
        ) { id in
            Button("Delete", role: .destructive) {
                store.removeWorkspace(id)
                deleteCandidate = nil
            }
            Button("Cancel", role: .cancel) { deleteCandidate = nil }
        } message: { _ in
            Text("This removes the workspace and all of its tabs. Running shells are not killed.")
        }
        .alert(
            L10n.Settings.shellCommand,  // reuse "Command" label
            isPresented: Binding(
                get: { commandEditTarget != nil },
                set: { if !$0 { commandEditTarget = nil } }
            ),
            presenting: commandEditTarget
        ) { id in
            TextField("e.g. npm run dev", text: $commandEditValue)
            Button("Save") {
                store.updateDefaultCommand(id, command: commandEditValue)
                commandEditTarget = nil
            }
            Button("Cancel", role: .cancel) { commandEditTarget = nil }
        } message: { _ in
            Text("Auto-runs in any new terminal opened inside this workspace.")
        }
    }

    /// Flatten the WorkspaceMetadataStore into the shape the bridge wants.
    private var metadataDictionary: [UUID: WorkspaceMetadataSnapshot] {
        metadata.snapshots
    }

    private func header(t: AppTheme) -> some View {
        HStack(spacing: DT.Space.md) {
            Spacer()
        }
        .frame(height: 58)
    }

    private func displayTitle(t: AppTheme) -> some View {
        HStack(alignment: .lastTextBaseline, spacing: DT.Space.md) {
            Text("IN0")
                .font(.system(size: 78, weight: .regular, design: .serif))
                .foregroundStyle(t.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.68)
            Text("DEV")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(t.textSecondary)
                .padding(.bottom, DT.Space.md)
            Spacer(minLength: 0)
        }
        .padding(.leading, DT.Space.xl)
        .padding(.trailing, DT.Space.lg)
        .padding(.bottom, DT.Space.sm)
        .accessibilityHidden(true)
    }

    private func footer(t: AppTheme) -> some View {
        HStack(spacing: DT.Space.xs) {
            Button {
                NotificationCenter.default.post(
                    name: .in0OpenSettings,
                    object: nil,
                    userInfo: ["section": SettingsSection.update.rawValue]
                )
            } label: {
                HStack(spacing: DT.Space.xs) {
                    Text("in0")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(t.textPrimary)
                    Text("v\(versionString)")
                        .font(.system(size: 12))
                        .foregroundStyle(t.textSecondary)
                    if updateStore.hasUpdate {
                        Circle()
                            .fill(t.danger)
                            .frame(width: 6, height: 6)
                    }
                }
            }
            .buttonStyle(.plain)
            .help("Check for updates")
            Spacer()
            Button {
                NotificationCenter.default.post(name: .in0OpenSettings, object: nil)
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(t.textSecondary)
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(.plain)
            .help("Settings")
        }
        .padding(.leading, DT.Space.xl)
        .padding(.trailing, DT.Space.lg)
        .padding(.vertical, DT.Space.sm)
    }

    private var versionString: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "0.0.0"
    }
}
