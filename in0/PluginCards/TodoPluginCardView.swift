import SwiftUI

struct TodoPluginCardView: View {
    @Environment(ThemeManager.self) private var theme
    @Environment(TodoStore.self) private var todos

    let workspace: Workspace
    @State private var draft = ""

    var body: some View {
        let t = theme.currentTheme
        let items = todos.items(for: workspace.id)
        let open = items.filter { !$0.isDone }
        let doneCount = items.count - open.count

        PluginCardContainer(title: "Todo", trailing: "\(open.count) open") {
            VStack(alignment: .leading, spacing: DT.Space.sm) {
                HStack(spacing: DT.Space.xs) {
                    TextField("Add a task...", text: $draft)
                        .textFieldStyle(.plain)
                        .font(.system(size: 11))
                        .onSubmit(addDraft)
                    Button(action: addDraft) {
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .buttonStyle(.borderless)
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(.horizontal, DT.Space.sm)
                .padding(.vertical, 6)
                .background(t.sidebar.opacity(0.9))
                .clipShape(RoundedRectangle(cornerRadius: DT.Radius.md, style: .continuous))

                if items.isEmpty {
                    Text("No tasks for this workspace.")
                        .font(.system(size: 11))
                        .foregroundStyle(t.textSecondary)
                } else {
                    ForEach(items.prefix(5)) { item in
                        HStack(alignment: .firstTextBaseline, spacing: DT.Space.xs) {
                            Button {
                                todos.setDone(item.id, !item.isDone)
                            } label: {
                                Image(systemName: item.isDone ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 12))
                                    .foregroundStyle(item.isDone ? t.success : t.textTertiary)
                            }
                            .buttonStyle(.plain)
                            Text(item.title)
                                .font(.system(size: 11))
                                .foregroundStyle(item.isDone ? t.textTertiary : t.textPrimary)
                                .strikethrough(item.isDone)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                        }
                    }
                }

                HStack {
                    Text("\(open.count) open · \(doneCount) done")
                        .font(.system(size: 10))
                        .foregroundStyle(t.textTertiary)
                    Spacer()
                    if doneCount > 0 {
                        Button("Clear Done") {
                            todos.clearDone(in: workspace.id)
                        }
                        .font(.system(size: 10))
                        .buttonStyle(.plain)
                        .foregroundStyle(t.textSecondary)
                    }
                }
            }
        }
    }

    private func addDraft() {
        guard todos.add(title: draft, workspaceId: workspace.id) != nil else { return }
        draft = ""
    }
}
