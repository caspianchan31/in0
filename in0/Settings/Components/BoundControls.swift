import SwiftUI

private enum SettingsControlMetrics {
    static let valueWidth: CGFloat = 420
    static let sliderWidth: CGFloat = 320
    static let numberWidth: CGFloat = 48
}

// MARK: - BoundToggle

/// Toggle bound to a `SettingsConfigStore` key. The default value is what
/// the toggle reports when the key is absent; setting it back to the
/// default removes the key from the on-disk config so the file stays
/// minimal — only user overrides are written.
struct BoundToggle: View {
    let settings: SettingsConfigStore
    let key: String
    let defaultValue: Bool
    let label: LocalizedStringResource

    var body: some View {
        Toggle(isOn: Binding(
            get: {
                guard let raw = settings.get(key) else { return defaultValue }
                return raw.lowercased() == "true"
            },
            set: { new in
                if new == defaultValue {
                    settings.set(key, nil)
                } else {
                    settings.set(key, new ? "true" : "false")
                }
            }
        )) {
            Text(label)
        }
    }
}

// MARK: - BoundSlider

/// Continuous slider bound to a numeric config key. Uses `setLive` so the
/// throttle gives smooth visual feedback while dragging without thrashing
/// disk + downstream reload. Step rounding lives in the setter — no tick
/// marks are drawn on the track.
struct BoundSlider: View {
    let settings: SettingsConfigStore
    let key: String
    let defaultValue: Double
    let range: ClosedRange<Double>
    let step: Double
    let label: LocalizedStringResource

    @Environment(\.locale) private var locale

    var body: some View {
        let value = Binding<Double>(
            get: {
                guard let raw = settings.get(key), let v = Double(raw) else { return defaultValue }
                return v
            },
            set: { new in
                let rounded = (new / step).rounded() * step
                if abs(rounded - defaultValue) < step / 2 {
                    settings.setLive(key, nil)
                } else {
                    settings.setLive(key, Self.format(rounded))
                }
            }
        )
        return LabeledContent(String(localized: label.withLocale(locale))) {
            HStack(spacing: DT.Space.sm) {
                Slider(value: value, in: range)
                    .frame(width: SettingsControlMetrics.sliderWidth)
                Text(Self.format(value.wrappedValue))
                    .monospacedDigit()
                    .frame(width: SettingsControlMetrics.numberWidth, alignment: .trailing)
                    .fixedSize()
            }
            .frame(width: SettingsControlMetrics.valueWidth, alignment: .trailing)
        }
    }

    private static func format(_ v: Double) -> String {
        if v == floor(v) { return String(Int(v)) }
        return String(format: "%.2f", v)
    }
}

// MARK: - BoundStepper

/// Integer stepper bound to a config key. Same default-elision semantics
/// as BoundToggle — setting the default writes nil so the file row goes away.
struct BoundStepper: View {
    let settings: SettingsConfigStore
    let key: String
    let defaultValue: Int
    let range: ClosedRange<Int>
    let label: LocalizedStringResource

    @Environment(\.locale) private var locale

    var body: some View {
        let value = Binding<Int>(
            get: {
                guard let raw = settings.get(key), let v = Int(raw) else { return defaultValue }
                return v
            },
            set: { new in
                let clamped = min(max(new, range.lowerBound), range.upperBound)
                if clamped == defaultValue {
                    settings.set(key, nil)
                } else {
                    settings.set(key, String(clamped))
                }
            }
        )
        return LabeledContent(String(localized: label.withLocale(locale))) {
            HStack(spacing: DT.Space.sm) {
                Stepper("", value: value, in: range).labelsHidden()
                    .accessibilityLabel(String(localized: label.withLocale(locale)))
                Text("\(value.wrappedValue)")
                    .monospacedDigit()
                    .frame(width: SettingsControlMetrics.numberWidth, alignment: .trailing)
                    .fixedSize()
            }
            .frame(width: SettingsControlMetrics.valueWidth, alignment: .trailing)
        }
    }
}

// MARK: - BoundTextField

/// Plain-text field bound to a config key. Empty / whitespace input clears
/// the key (no row written). Trims on commit, not on every keystroke, to
/// preserve in-progress IME composition.
struct BoundTextField: View {
    let settings: SettingsConfigStore
    let theme: AppTheme
    let key: String
    let placeholder: LocalizedStringResource
    let label: LocalizedStringResource

    @Environment(\.locale) private var locale

    var body: some View {
        LabeledContent(String(localized: label.withLocale(locale))) {
            TextField(String(localized: placeholder.withLocale(locale)), text: Binding(
                get: { settings.get(key) ?? "" },
                set: { new in
                    let trimmed = new.trimmingCharacters(in: .whitespaces)
                    settings.set(key, trimmed.isEmpty ? nil : trimmed)
                }
            ))
            .themedTextField(theme)
            .frame(width: SettingsControlMetrics.valueWidth)
        }
    }
}

// MARK: - BoundSegmented

/// Dropdown bound to a string config key. The first option is treated as
/// the default and its selection removes the key from the file.
struct BoundSegmented: View {
    let settings: SettingsConfigStore
    let key: String
    let options: [String]
    let label: LocalizedStringResource

    @Environment(\.locale) private var locale

    var body: some View {
        let binding = Binding<String>(
            get: { settings.get(key) ?? options.first ?? "" },
            set: { new in
                if new == options.first {
                    settings.set(key, nil)
                } else {
                    settings.set(key, new)
                }
            }
        )
        return LabeledContent(String(localized: label.withLocale(locale))) {
            Picker("", selection: binding) {
                ForEach(options, id: \.self) { Text($0).tag($0) }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .accessibilityLabel(String(localized: label.withLocale(locale)))
            .frame(width: SettingsControlMetrics.valueWidth, alignment: .trailing)
        }
    }
}

// MARK: - BoundMultiSelect

struct BoundMultiSelect: View {
    let settings: SettingsConfigStore
    let key: String
    let allOptions: [String]
    let label: LocalizedStringResource

    @Environment(\.locale) private var locale

    var body: some View {
        LabeledContent(String(localized: label.withLocale(locale))) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: DT.Space.md) {
                    checkboxGroup
                }
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 96), spacing: DT.Space.sm)],
                    alignment: .trailing,
                    spacing: DT.Space.xs
                ) {
                    checkboxGroup
                }
            }
            .frame(width: SettingsControlMetrics.valueWidth, alignment: .trailing)
        }
    }

    @ViewBuilder
    private var checkboxGroup: some View {
        ForEach(allOptions, id: \.self) { option in
            Toggle(option, isOn: binding(for: option))
                .toggleStyle(.checkbox)
                .fixedSize()
        }
    }

    private func binding(for option: String) -> Binding<Bool> {
        Binding(
            get: { selectedOptions.contains(option) },
            set: { isOn in
                var selected = selectedOptions
                if isOn {
                    selected.insert(option)
                } else {
                    selected.remove(option)
                }
                let ordered = allOptions.filter { selected.contains($0) }
                settings.set(key, ordered.isEmpty ? nil : ordered.joined(separator: ","))
            }
        )
    }

    private var selectedOptions: Set<String> {
        guard let raw = settings.get(key) else { return [] }
        return Set(raw
            .split { $0 == "," || $0 == " " }
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty })
    }
}
