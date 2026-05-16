import SwiftUI

/// One Settings-list row for a quick action. Renders icon + name (read-only
/// for built-ins, editable for custom) + command field + enable toggle +
/// optional delete button (custom only). Every edit funnels through
/// `QuickActionsStore` — this view holds no state of its own beyond the
/// FocusState shims needed to make the row's empty space act as a
/// clickable focus target (SwiftUI's TextField doesn't capture taps in
/// the padding around the field).
struct QuickActionRowView: View {
    let id: QuickActionId
    let store: QuickActionsStore
    let theme: AppTheme
    let isBuiltin: Bool

    @Environment(\.locale) private var locale
    @FocusState private var nameFocused: Bool
    @FocusState private var commandFocused: Bool

    var body: some View {
        HStack(spacing: DT.Space.sm) {
            QuickActionIconView(
                source: store.iconSource(for: id),
                size: 13,
                color: theme.textSecondary
            )
            .frame(width: 17)

            if isBuiltin {
                Text(store.displayName(for: id, locale: locale))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(width: 128, alignment: .leading)
                    .foregroundColor(theme.textPrimary)
            } else {
                TextField(
                    String(localized: L10n.Settings.QuickActions.customNamePlaceholder.withLocale(locale)),
                    text: nameBinding
                )
                .themedTextField(theme)
                .frame(width: 128)
                .focused($nameFocused)
                .contentShape(Rectangle())
                .onTapGesture { nameFocused = true }
                .accessibilityLabel("Quick action name")
            }

            TextField(commandPlaceholder, text: commandBinding)
                .themedTextField(theme)
                .frame(minWidth: 180, maxWidth: .infinity)
                .focused($commandFocused)
                .contentShape(Rectangle())
                .onTapGesture { commandFocused = true }
                .accessibilityLabel("Quick action command")

            Toggle("", isOn: enabledBinding)
                .toggleStyle(.switch)
                .controlSize(.mini)
                .labelsHidden()
                .accessibilityLabel("Enable \(store.displayName(for: id, locale: locale))")

            if !isBuiltin {
                Button {
                    store.removeCustomAction(id)
                } label: {
                    Image(systemName: "trash")
                        .foregroundColor(theme.textTertiary)
                }
                .buttonStyle(.borderless)
                .help(String(localized: L10n.Settings.QuickActions.deleteCustomTooltip.withLocale(locale)))
                .accessibilityLabel(String(localized: L10n.Settings.QuickActions.deleteCustomTooltip.withLocale(locale)))
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - Bindings

    private var nameBinding: Binding<String> {
        Binding(
            get: { store.customActions.first(where: { $0.id == id })?.name ?? "" },
            set: { store.updateCustomAction(id, name: $0) }
        )
    }

    private var commandBinding: Binding<String> {
        Binding(
            get: {
                if isBuiltin {
                    return store.builtinCommandOverrides[id] ?? ""
                }
                return store.customActions.first(where: { $0.id == id })?.command ?? ""
            },
            set: { new in
                if isBuiltin {
                    store.setBuiltinCommand(id, new)
                } else {
                    store.updateCustomAction(id, command: new)
                }
            }
        )
    }

    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { store.isEnabled(id) },
            set: { store.setEnabled(id, $0) }
        )
    }

    private var commandPlaceholder: String {
        if let builtin = BuiltinQuickAction.from(id: id) {
            return builtin.defaultCommand
        }
        return String(localized: L10n.Settings.QuickActions.customCommandPlaceholder.withLocale(locale))
    }
}
