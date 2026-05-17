import SwiftUI

struct PluginCardSidebarView: View {
    @Environment(ThemeManager.self) private var theme
    @Environment(WorkspaceStore.self) private var workspaces
    @Environment(PluginStore.self) private var plugins
    @Environment(PluginCardStore.self) private var cardStore

    var body: some View {
        let t = theme.currentTheme
        VStack(alignment: .leading, spacing: DT.Space.md) {
            header(t)
            ScrollView {
                VStack(spacing: DT.Space.sm) {
                    if let workspace = workspaces.selectedWorkspace {
                        ForEach(plugins.visibleWorkspaceCards) { card in
                            cardView(card, workspace: workspace)
                        }
                        if plugins.visibleWorkspaceCards.isEmpty {
                            emptyState(t)
                        }
                    } else {
                        emptyState(t)
                    }
                }
                .padding(.horizontal, DT.Space.sm)
                .padding(.bottom, DT.Space.sm)
            }
            .scrollIndicators(.never)
        }
        .background(t.sidebar.opacity(theme.backgroundOpacity))
        .overlay(alignment: .leading) {
            ResizeHandle()
                .environment(cardStore)
                .environment(theme)
        }
        .clipShape(RoundedRectangle(cornerRadius: DT.Radius.lg, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: DT.Radius.lg, style: .continuous)
                .strokeBorder(t.border.opacity(0.7), lineWidth: DT.Stroke.hairline)
        }
    }

    private func header(_ t: AppTheme) -> some View {
        HStack(spacing: DT.Space.sm) {
            Text("Plugin Cards")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(t.textPrimary)
            Spacer()
            IconButton(theme: t, help: "Hide plugin cards") {
                withAnimation(.easeInOut(duration: 0.18)) {
                    cardStore.setOpen(false)
                }
            } label: {
                Image(systemName: "sidebar.right")
                    .font(.system(size: 13, weight: .semibold))
            }
        }
        .padding(.leading, DT.Space.lg)
        .padding(.trailing, DT.Space.sm)
        .padding(.top, DT.Space.md)
    }

    @ViewBuilder
    private func cardView(_ card: PluginCardSurface, workspace: Workspace) -> some View {
        switch card.id {
        case "todo":
            TodoPluginCardView(workspace: workspace)
        case "github-scan":
            GitHubScanPluginCardView(workspace: workspace)
        case "agent-status":
            AgentStatusPluginCardView(workspace: workspace)
        case "ai-history":
            AIHistoryPluginCardView(workspace: workspace)
        default:
            GenericPluginCardView(card: card)
        }
    }

    private func emptyState(_ t: AppTheme) -> some View {
        PluginCardContainer(title: "No Cards") {
            Text("Enable plugins in Settings to show cards here.")
                .font(.system(size: 11))
                .foregroundStyle(t.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct PluginCardCollapsedHandle: View {
    @Environment(ThemeManager.self) private var theme
    @Environment(PluginCardStore.self) private var cardStore

    var body: some View {
        let t = theme.currentTheme
        Button {
            withAnimation(.easeInOut(duration: 0.18)) {
                cardStore.setOpen(true)
            }
        } label: {
            Image(systemName: "sidebar.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(t.textSecondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .padding(.top, DT.Space.md)
        }
        .buttonStyle(.plain)
        .background(t.sidebar.opacity(theme.backgroundOpacity))
        .clipShape(RoundedRectangle(cornerRadius: DT.Radius.lg, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: DT.Radius.lg, style: .continuous)
                .strokeBorder(t.border.opacity(0.7), lineWidth: DT.Stroke.hairline)
        }
    }
}

private struct ResizeHandle: View {
    @Environment(PluginCardStore.self) private var store
    @Environment(ThemeManager.self) private var theme
    @State private var startWidth: CGFloat?

    var body: some View {
        Rectangle()
            .fill(theme.currentTheme.border.opacity(0.75))
            .frame(width: 1)
            .contentShape(Rectangle().inset(by: -4))
            .gesture(
                DragGesture()
                    .onChanged { value in
                        if startWidth == nil { startWidth = store.width }
                        store.setWidth((startWidth ?? store.width) - value.translation.width)
                    }
                    .onEnded { _ in startWidth = nil }
            )
    }
}

struct PluginCardContainer<Content: View>: View {
    @Environment(ThemeManager.self) private var theme
    let title: String
    let trailing: String?
    let content: Content

    init(title: String, trailing: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.trailing = trailing
        self.content = content()
    }

    var body: some View {
        let t = theme.currentTheme
        VStack(alignment: .leading, spacing: DT.Space.sm) {
            HStack(spacing: DT.Space.xs) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(t.textPrimary)
                Spacer()
                if let trailing {
                    Text(trailing)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(t.textTertiary)
                }
            }
            content
        }
        .padding(DT.Space.md)
        .background(t.selection.opacity(0.46))
        .clipShape(RoundedRectangle(cornerRadius: DT.Radius.lg, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: DT.Radius.lg, style: .continuous)
                .strokeBorder(t.border.opacity(0.65), lineWidth: DT.Stroke.hairline)
        }
    }
}

private struct GenericPluginCardView: View {
    @Environment(ThemeManager.self) private var theme
    let card: PluginCardSurface

    var body: some View {
        PluginCardContainer(title: card.title) {
            Text(card.summary)
                .font(.system(size: 11))
                .foregroundStyle(theme.currentTheme.textSecondary)
        }
    }
}
