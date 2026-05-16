import AppKit

@MainActor
/// Parses ghostty's config + referenced theme files to extract background /
/// foreground / palette colors. We read text directly rather than going
/// through libghostty's getter API — the C API for typed config queries
/// has unstable key semantics, and we already understand the file format.
///
/// Sources, in increasing priority order:
///   1. Ghostty's own config (`~/.config/ghostty/config` or the legacy
///      `Application Support/com.mitchellh.ghostty/config`).
///   2. The in0 override config (`~/Library/Application Support/in0/config`).
///   3. The `theme = Name` reference inside the merged config, resolved
///      against `themeSearchPaths`. (Theme files are read AFTER direct
///      background/foreground assignments, so a direct
///      `background = #112233` wins over a theme's own background.)
enum GhosttyConfigReader {

    struct Colors {
        var background: NSColor?
        var foreground: NSColor?
        var palette: [Int: NSColor] = [:]
    }

    static var configPaths: [String] {
        let home = NSHomeDirectory()
        return [
            "\(home)/Library/Application Support/com.mitchellh.ghostty/config",
            "\(home)/.config/ghostty/config",
        ]
    }

    /// Directories scanned (in order) for theme files. User-installed themes
    /// win over the bundled-with-Ghostty.app set so a user can override a
    /// theme by name without renaming.
    static var themeSearchPaths: [String] {
        let home = NSHomeDirectory()
        var paths = [
            "\(home)/.config/ghostty/themes",
            "\(home)/Library/Application Support/com.mitchellh.ghostty/themes",
            "/Applications/Ghostty.app/Contents/Resources/ghostty/themes",
        ]
        if let resBase = Bundle.main.resourcePath {
            paths.append((resBase as NSString).appendingPathComponent("ghostty/themes"))
        }
        return paths
    }

    /// Resolves the effective colors visible to in0's chrome.
    static func load() -> Colors {
        var themeColors = Colors()
        var direct = Colors()

        var merged: [(String, String)] = []
        for path in configPaths where FileManager.default.fileExists(atPath: path) {
            merged.append(contentsOf: parseFile(at: path))
            break
        }
        let in0Path = SettingsConfigStore.defaultPath
        if FileManager.default.fileExists(atPath: in0Path) {
            merged.append(contentsOf: parseFile(at: in0Path))
        }

        // `theme` resolves to the last non-empty assignment (in0 overrides
        // ghostty), then the theme file's own kv pairs are walked into the
        // theme bucket.
        if let raw = merged.reversed().first(where: { $0.0 == "theme" })?.1, !raw.isEmpty {
            let name = resolveThemeNameForAppearance(raw)
            if let themePath = locateTheme(named: name) {
                applyKVs(parseFile(at: themePath), into: &themeColors)
            }
        }
        applyKVs(merged, into: &direct)

        return Colors(
            background: direct.background ?? themeColors.background,
            foreground: direct.foreground ?? themeColors.foreground,
            palette: themeColors.palette.merging(direct.palette) { _, new in new }
        )
    }

    /// Honors ghostty's `theme = light:Name1,dark:Name2` syntax: picks the
    /// side matching the system's current appearance.
    private static func resolveThemeNameForAppearance(_ raw: String) -> String {
        guard raw.contains(":") && raw.contains(",") else { return raw }
        let isDark = NSApp?.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let prefix = isDark ? "dark:" : "light:"
        for part in raw.split(separator: ",") {
            let p = part.trimmingCharacters(in: .whitespaces)
            if p.hasPrefix(prefix) { return String(p.dropFirst(prefix.count)) }
        }
        return raw
    }

    // MARK: - File parsing

    /// Parses a ghostty-style config file into (key, value) pairs. Keys may
    /// repeat (e.g. `palette = 1 = #ff0000` followed by `palette = 2 = ...`).
    /// Lines starting with `#` and blank lines are skipped.
    static func parseFile(at path: String) -> [(String, String)] {
        guard let contents = try? String(contentsOfFile: path, encoding: .utf8) else { return [] }
        var result: [(String, String)] = []
        for raw in contents.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#") else { continue }
            guard let eq = line.firstIndex(of: "=") else { continue }
            let key = String(line[..<eq]).trimmingCharacters(in: .whitespaces)
            var value = String(line[line.index(after: eq)...]).trimmingCharacters(in: .whitespaces)
            if value.hasPrefix("\"") && value.hasSuffix("\"") && value.count >= 2 {
                value = String(value.dropFirst().dropLast())
            }
            result.append((key, value))
        }
        return result
    }

    private static func applyKVs(_ kvs: [(String, String)], into colors: inout Colors) {
        for (key, value) in kvs {
            switch key {
            case "background":
                if let c = parseColor(value) { colors.background = c }
            case "foreground":
                if let c = parseColor(value) { colors.foreground = c }
            case "palette":
                // value looks like "3=#df8e1d"
                if let eq = value.firstIndex(of: "="),
                   let idx = Int(value[..<eq]),
                   let c = parseColor(String(value[value.index(after: eq)...])) {
                    colors.palette[idx] = c
                }
            default: break
            }
        }
    }

    // MARK: - Theme lookup

    static func resolvedThemePath() -> String? {
        let sources = [SettingsConfigStore.defaultPath] + configPaths
        for path in sources where FileManager.default.fileExists(atPath: path) {
            let kvs = parseFile(at: path)
            guard let raw = kvs.first(where: { $0.0 == "theme" })?.1, !raw.isEmpty else { continue }
            return locateTheme(named: resolveThemeNameForAppearance(raw))
        }
        return nil
    }

    static func locateTheme(named name: String) -> String? {
        for dir in themeSearchPaths {
            let candidate = "\(dir)/\(name)"
            if FileManager.default.fileExists(atPath: candidate) { return candidate }
        }
        return nil
    }

    // MARK: - Color parsing

    /// Accepts `#rgb`, `#rrggbb`, `rgb:rr/gg/bb`. Named ghostty palette
    /// constants are not resolved here (they're rare in user configs and
    /// noticeably increase parser complexity); they fall through to nil.
    static func parseColor(_ raw: String) -> NSColor? {
        var s = raw.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s = String(s.dropFirst()) }
        if s.hasPrefix("rgb:") {
            let body = String(s.dropFirst(4))
            let parts = body.components(separatedBy: "/")
            guard parts.count == 3,
                  let r = UInt8(parts[0], radix: 16),
                  let g = UInt8(parts[1], radix: 16),
                  let b = UInt8(parts[2], radix: 16) else { return nil }
            return NSColor(srgbRed: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: 1)
        }
        if s.count == 3 {
            // #rgb shorthand → expand each char.
            let chars = Array(s)
            return parseColor("#\(chars[0])\(chars[0])\(chars[1])\(chars[1])\(chars[2])\(chars[2])")
        }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        let r = CGFloat((v >> 16) & 0xff) / 255
        let g = CGFloat((v >>  8) & 0xff) / 255
        let b = CGFloat( v        & 0xff) / 255
        return NSColor(srgbRed: r, green: g, blue: b, alpha: 1)
    }
}
