import Foundation

/// Lists ghostty themes available on disk. Themes ship in three places:
///   1. `~/.config/ghostty/themes/` — user-installed (highest priority).
///   2. `<bundle>/Contents/Resources/ghostty/themes/` — bundled with in0
///      via `scripts/build-vendor.sh` (the standard `libghostty.a` pack).
///   3. `/Applications/Ghostty.app/Contents/Resources/ghostty/themes/` —
///      a parallel ghostty install, if the user has the standalone app.
///
/// All three are merged + deduped. The list is cached after first access
/// because `FileManager.contentsOfDirectory` on the 600-entry themes dir
/// adds ~5ms each time, and the list never changes mid-session.
@MainActor
enum ThemeCatalog {
    /// Cached sorted list of every theme name in0 can render.
    static let all: [String] = scan()

    /// Async-safe accessor used by older call sites. Identical to `.all`
    /// but written as a function to avoid a "main-actor isolated static
    /// property read from non-isolated context" complaint when Settings
    /// section views call it from `.onAppear`.
    static func available() -> [String] { all }

    /// Scan a single directory for theme files. Public so tests can drive
    /// it with a tmp dir; `scan()` (no args) walks the merged search path.
    static func scan(atPath path: String) -> [String] {
        let url = URL(fileURLWithPath: path, isDirectory: true)
        guard let items = try? FileManager.default.contentsOfDirectory(
            at: url, includingPropertiesForKeys: nil
        ) else { return [] }
        return items
            .filter { !$0.lastPathComponent.hasPrefix(".") }
            .map(\.lastPathComponent)
            .sorted()
    }

    private static func scan() -> [String] {
        let fm = FileManager.default
        var names: Set<String> = []
        var dirs: [URL] = [
            fm.homeDirectoryForCurrentUser
                .appendingPathComponent(".config", isDirectory: true)
                .appendingPathComponent("ghostty", isDirectory: true)
                .appendingPathComponent("themes", isDirectory: true),
            URL(fileURLWithPath: "/Applications/Ghostty.app/Contents/Resources/ghostty/themes",
                isDirectory: true),
        ]
        if let bundle = Bundle.main.resourceURL?
            .appendingPathComponent("ghostty", isDirectory: true)
            .appendingPathComponent("themes", isDirectory: true) {
            dirs.append(bundle)
        }
        for dir in dirs {
            guard let items = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { continue }
            for url in items where !url.lastPathComponent.hasPrefix(".") {
                names.insert(url.lastPathComponent)
            }
        }
        return names.sorted()
    }
}
