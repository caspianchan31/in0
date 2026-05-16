import SwiftUI

/// Theme selector. Renders as three LabeledContent rows:
///   1. Mode (Single / Follow system).
///   2. Single-mode name (or Light name in follow-system mode).
///   3. Dark-mode name (collapsed to opacity 0 in Single mode so the row
///      doesn't reflow when the user flips the mode).
///
/// Backed by the `theme` key in `SettingsConfigStore`. The follow-system
/// form serializes as `theme = light:Catppuccin Latte,dark:Catppuccin Macchiato`,
/// matching ghostty's own syntax so the picker round-trips with hand
/// edits.
struct ThemePickerView: View {
    let settings: SettingsConfigStore
    let theme: AppTheme

    enum Mode: String, CaseIterable, Identifiable {
        case single, followSystem
        var id: String { rawValue }
    }

    @State private var mode: Mode = .single
    @State private var singleName: String = ""
    @State private var lightName: String = ""
    @State private var darkName: String = ""
    /// Latches once the view loads the persisted state so subsequent
    /// rebuilds (section navigation, theme refresh) don't trample over a
    /// half-typed value during the 200 ms debounce window.
    @State private var didLoad = false

    @Environment(\.locale) private var locale

    var body: some View {
        Group {
            LabeledContent(String(localized: L10n.Settings.theme.withLocale(locale))) {
                HStack {
                    Spacer(minLength: 0)
                    Picker("", selection: $mode) {
                        ForEach(Mode.allCases) { m in
                            Text(m == .single ? L10n.Settings.themeSingle : L10n.Settings.themeFollowSystem)
                                .tag(m)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .fixedSize()
                    .onChange(of: mode) { _, _ in writeBack() }
                }
            }

            LabeledContent(String(localized: (mode == .single
                                              ? L10n.Settings.themeName
                                              : L10n.Settings.themeLight).withLocale(locale))) {
                HStack {
                    Spacer(minLength: 0)
                    ThemeDropdown(
                        selection: Binding(
                            get: { mode == .single ? singleName : lightName },
                            set: {
                                if mode == .single { singleName = $0 } else { lightName = $0 }
                                writeBack()
                            }
                        ),
                        theme: theme
                    )
                }
            }

            LabeledContent(String(localized: L10n.Settings.themeDark.withLocale(locale))) {
                HStack {
                    Spacer(minLength: 0)
                    ThemeDropdown(
                        selection: Binding(
                            get: { darkName },
                            set: { darkName = $0; writeBack() }
                        ),
                        theme: theme
                    )
                }
            }
            .opacity(mode == .followSystem ? 1 : 0)
            .allowsHitTesting(mode == .followSystem)
        }
        .onAppear {
            guard !didLoad else { return }
            didLoad = true
            loadFromStore()
        }
    }

    private func loadFromStore() {
        guard let raw = settings.get("theme"), !raw.isEmpty else {
            mode = .single
            singleName = ""
            lightName = ""
            darkName = ""
            return
        }
        if raw.hasPrefix("light:") || raw.contains(",dark:") {
            mode = .followSystem
            for part in raw.split(separator: ",") {
                let p = part.trimmingCharacters(in: .whitespaces)
                if p.hasPrefix("light:") {
                    lightName = String(p.dropFirst("light:".count))
                } else if p.hasPrefix("dark:") {
                    darkName = String(p.dropFirst("dark:".count))
                }
            }
        } else {
            mode = .single
            singleName = raw
        }
    }

    private func writeBack() {
        switch mode {
        case .single:
            let v = singleName.trimmingCharacters(in: .whitespaces)
            settings.set("theme", v.isEmpty ? nil : v)
        case .followSystem:
            let l = lightName.trimmingCharacters(in: .whitespaces)
            let d = darkName.trimmingCharacters(in: .whitespaces)
            if l.isEmpty && d.isEmpty {
                settings.set("theme", nil)
            } else if !l.isEmpty && !d.isEmpty {
                settings.set("theme", "light:\(l),dark:\(d)")
            }
            // Only one side filled → don't write a half-formed
            // `theme = light:X,dark:` that ghostty would reject.
        }
    }
}

/// Searchable theme dropdown. Uses a popover (not `Menu`) because
/// `NSMenu` doesn't render TextField / ScrollView children — anything
/// non-menu-item gets dropped.
private struct ThemeDropdown: View {
    @Binding var selection: String
    let theme: AppTheme

    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.locale) private var locale
    @State private var open = false
    @State private var query = ""

    var body: some View {
        Button {
            open.toggle()
        } label: {
            HStack(spacing: 4) {
                Text(selection.isEmpty
                     ? String(localized: L10n.Settings.themeInherit.withLocale(locale))
                     : selection)
                    .foregroundStyle(theme.textPrimary)
                Spacer(minLength: 0)
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(theme.textSecondary)
            }
            .frame(minWidth: 220, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: DT.Radius.row, style: .continuous)
                    .fill(theme.sidebar.opacity(themeManager.contentEffectiveOpacity))
            )
            .overlay(
                RoundedRectangle(cornerRadius: DT.Radius.row, style: .continuous)
                    .strokeBorder(theme.border.opacity(themeManager.contentEffectiveOpacity), lineWidth: 0.5)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .popover(isPresented: $open, arrowEdge: .bottom) {
            ThemeDropdownPanel(
                query: $query,
                selection: Binding(
                    get: { selection },
                    set: { selection = $0; open = false }
                ),
                theme: theme
            )
            .frame(width: 280, height: 340)
        }
    }
}

private struct ThemeDropdownPanel: View {
    @Binding var query: String
    @Binding var selection: String
    let theme: AppTheme

    @Environment(\.locale) private var locale

    /// Sentinel row id for the "inherit" entry. Real theme names go in
    /// `ForEach(id: \.self)`; we don't want to collide with `""`.
    private static let inheritRowID = "__in0_inherit__"

    var body: some View {
        VStack(spacing: 0) {
            TextField(String(localized: L10n.Settings.themeSearchPlaceholder.withLocale(locale)), text: $query)
                .themedTextField(theme)
                .padding(DT.Space.sm)

            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        if query.isEmpty {
                            ThemeRow(
                                name: String(localized: L10n.Settings.themeInherit.withLocale(locale)),
                                isSelected: selection.isEmpty,
                                theme: theme
                            ) { selection = "" }
                            .id(Self.inheritRowID)
                        }
                        ForEach(filtered, id: \.self) { name in
                            ThemeRow(name: name, isSelected: name == selection, theme: theme) {
                                selection = name
                            }
                            .id(name)
                        }
                    }
                }
                .onAppear {
                    // LazyVStack populates a frame after layout, so a
                    // direct scrollTo on .onAppear fails — bounce through
                    // the main queue once.
                    DispatchQueue.main.async {
                        proxy.scrollTo(selection.isEmpty ? Self.inheritRowID : selection, anchor: .center)
                    }
                }
            }
        }
        .background(theme.canvas)
        // Popovers spawn their own NSWindow; without an explicit color
        // scheme the TextField's `.roundedBorder` would render with the
        // system's appearance and clash with our chrome.
        .preferredColorScheme(theme.isDark ? .dark : .light)
    }

    private var filtered: [String] {
        let all = ThemeCatalog.all
        guard !query.isEmpty else { return all }
        let lower = query.lowercased()
        return all.filter { $0.lowercased().contains(lower) }
    }
}

private struct ThemeRow: View {
    let name: String
    let isSelected: Bool
    let theme: AppTheme
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack {
                Text(name)
                    .foregroundStyle(theme.textPrimary)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(theme.accent)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(hovering ? theme.border : .clear)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
