import AppKit
import SwiftUI

/// Monospace-font dropdown with a "Custom…" escape hatch. Backed by the
/// `font-family` key in `SettingsConfigStore`.
///
/// `NSFontManager.availableFontNames(with: .fixedPitchFontMask)` returns
/// PostScript names (e.g. `Menlo-Regular`); ghostty's `font-family`
/// expects the family name (`Menlo`), so we deduplicate by `familyName`
/// before showing the list.
struct FontPickerView: View {
    let settings: SettingsConfigStore
    let theme: AppTheme
    let label: LocalizedStringResource

    @State private var isCustom: Bool = false
    @Environment(\.locale) private var locale

    /// Cached on first access — querying NSFontManager runs an
    /// FT-walk that costs a few ms on large user fonts; once is enough.
    private static let systemMonospaceFonts: [String] = {
        let names = NSFontManager.shared.availableFontNames(with: .fixedPitchFontMask) ?? []
        let families = Set(names.compactMap { NSFont(name: $0, size: 12)?.familyName })
        return families.sorted()
    }()

    var body: some View {
        LabeledContent(String(localized: label.withLocale(locale))) {
            HStack {
                Spacer(minLength: 0)
                if isCustom {
                    TextField(String(localized: L10n.Settings.fontCustomPlaceholder.withLocale(locale)),
                              text: Binding(
                        get: { settings.get("font-family") ?? "" },
                        set: { settings.set("font-family", $0.isEmpty ? nil : $0) }
                    ))
                    .themedTextField(theme)
                    .frame(minWidth: 200)

                    Button {
                        // If the user typed an off-list font (Nerd Font / Iosevka SS),
                        // clear it before flipping back to the menu — otherwise the
                        // Picker would render with an empty selection bubble.
                        let current = settings.get("font-family") ?? ""
                        if !current.isEmpty && !Self.systemMonospaceFonts.contains(current) {
                            settings.set("font-family", nil)
                        }
                        isCustom = false
                    } label: {
                        Text(L10n.Settings.fontListButton)
                    }
                    .buttonStyle(.borderless)
                } else {
                    Picker("", selection: pickerBinding) {
                        Text(L10n.Settings.fontDefault).tag("")
                        ForEach(Self.systemMonospaceFonts, id: \.self) { Text($0).tag($0) }
                        Text(L10n.Settings.fontCustom).tag("__custom__")
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .fixedSize()
                }
            }
        }
        .onAppear {
            // If the persisted family isn't in the system list, drop into
            // Custom mode so the user can see + edit their value.
            if let current = settings.get("font-family"),
               !Self.systemMonospaceFonts.contains(current) {
                isCustom = true
            }
        }
    }

    private var pickerBinding: Binding<String> {
        Binding(
            get: { settings.get("font-family") ?? "" },
            set: { new in
                if new == "__custom__" {
                    isCustom = true
                } else if new.isEmpty {
                    settings.set("font-family", nil)
                } else {
                    settings.set("font-family", new)
                }
            }
        )
    }
}
