import AppKit
import Foundation

/// Singleton wrapper around the libghostty C API.
///
/// This is the only file (along with `GhosttyTerminalView`) that talks to
/// `ghostty_*` functions directly. Everything else goes through the API
/// declared here.
@MainActor
final class GhosttyBridge {
    static let shared = GhosttyBridge()

    private(set) var app: ghostty_app_t?
    private(set) var config: ghostty_config_t?

    /// Environment variables injected into every surface (e.g. so agent
    /// hook scripts know where the listener socket is).
    var defaultEnv: [String: String] = [:]

    /// Called whenever a surface emits its PWD via OSC 7.
    /// `(terminalId, pwd)`.
    var onPwdChanged: ((UUID, String) -> Void)?

    /// Called when ghostty signals a terminal color change. `kind` matches the
    /// libghostty enum: -1 foreground, -2 background, -3 cursor, otherwise an
    /// indexed palette slot.
    var onColorChange: ((_ kind: Int32, _ r: UInt8, _ g: UInt8, _ b: UInt8) -> Void)?

    /// Per-terminal scrollbar updates: (terminalId, total, offset, len).
    var onScrollbar: ((UUID, UInt64, UInt64, UInt64) -> Void)?

    private init() {}

    /// True after `initialize()` has produced a non-null `ghostty_app_t`.
    /// in0App branches its scene on this so libghostty-missing builds (CI,
    /// fresh clones without `./scripts/build-vendor.sh`) show
    /// `GhosttyMissingView` instead of a window that immediately crashes.
    var isInitialized: Bool { app != nil }

    /// Returns `true` on successful init or when already initialized; `false`
    /// when `ghostty_app_new` returned null.
    @discardableResult
    func initialize() -> Bool {
        if app != nil { return true }

        // ghostty_init must run before any other API call.
        let argv0 = strdup("in0")
        var argv: [UnsafeMutablePointer<CChar>?] = [argv0, nil]
        _ = argv.withUnsafeMutableBufferPointer { buf in
            ghostty_init(UInt(1), buf.baseAddress)
        }
        if let argv0 { free(argv0) }

        guard let cfg = buildConfig() else {
            assertionFailure("ghostty_config_new returned NULL")
            return false
        }
        self.config = cfg

        var runtime = ghostty_runtime_config_s()
        runtime.userdata = Unmanaged.passUnretained(self).toOpaque()
        runtime.supports_selection_clipboard = false
        runtime.wakeup_cb = wakeupCallback
        runtime.action_cb = actionCallback
        runtime.read_clipboard_cb = readClipboardCallback
        runtime.confirm_read_clipboard_cb = confirmReadClipboardCallback
        runtime.write_clipboard_cb = writeClipboardCallback
        runtime.close_surface_cb = closeSurfaceCallback

        guard let appPtr = ghostty_app_new(&runtime, cfg) else {
            assertionFailure("ghostty_app_new returned NULL")
            return false
        }
        self.app = appPtr
        return true
    }

    func tick() {
        guard let app else { return }
        ghostty_app_tick(app)
    }

    func teardown() {
        if let app {
            ghostty_app_free(app)
            self.app = nil
        }
        if let config {
            ghostty_config_free(config)
            self.config = nil
        }
    }

    // MARK: - Config build / reload

    /// Build a fresh libghostty config from ghostty defaults, bundled
    /// resources, the resolved theme file, and in0's override config.
    /// GUI settings write to that override file, so this is the single
    /// path used for both launch and hot reload.
    private func buildConfig() -> ghostty_config_t? {
        guard let cfg = ghostty_config_new() else { return nil }
        ghostty_config_load_default_files(cfg)

        let cacheDir = (NSHomeDirectory() as NSString)
            .appendingPathComponent("Library/Caches/in0")
        try? FileManager.default.createDirectory(
            atPath: cacheDir,
            withIntermediateDirectories: true
        )

        let defaultsPath = (cacheDir as NSString).appendingPathComponent("in0-defaults.conf")
        let defaults = """
        window-padding-x = 4
        window-padding-y = 4
        cursor-style-blink = false
        """
        try? defaults.write(toFile: defaultsPath, atomically: true, encoding: .utf8)
        defaultsPath.withCString { ghostty_config_load_file(cfg, $0) }

        ghostty_config_load_recursive_files(cfg)

        if let resourcePath = Bundle.main.resourcePath {
            let ghosttyDir = (resourcePath as NSString).appendingPathComponent("ghostty")
            if FileManager.default.fileExists(atPath: ghosttyDir) {
                let tmpConf = (cacheDir as NSString).appendingPathComponent("resources-dir.conf")
                let body = "resources-dir = \(ghosttyDir)\nshell-integration = detect\n"
                try? body.write(toFile: tmpConf, atomically: true, encoding: .utf8)
                tmpConf.withCString { ghostty_config_load_file(cfg, $0) }
            } else {
                NSLog("in0: bundled ghostty resources missing at \(ghosttyDir)")
            }
        }

        if let themePath = GhosttyConfigReader.resolvedThemePath() {
            themePath.withCString { ghostty_config_load_file(cfg, $0) }
        }

        let in0Config = SettingsConfigStore.defaultPath
        if FileManager.default.fileExists(atPath: in0Config) {
            in0Config.withCString { ghostty_config_load_file(cfg, $0) }
        }

        let transparentConf = (cacheDir as NSString)
            .appendingPathComponent("transparent-surface.conf")
        try? "background-opacity = 0\n".write(
            toFile: transparentConf,
            atomically: true,
            encoding: .utf8
        )
        transparentConf.withCString { ghostty_config_load_file(cfg, $0) }

        ghostty_config_finalize(cfg)
        return cfg
    }

    func reloadConfig() {
        guard let app else { return }
        guard let next = buildConfig() else {
            NSLog("in0: ghostty config reload failed")
            return
        }
        ghostty_app_update_config(app, next)
        for surface in GhosttyTerminalView.allLiveSurfaces() {
            ghostty_surface_update_config(surface, next)
        }
        if let config {
            ghostty_config_free(config)
        }
        config = next
    }

    func applyWindowBackgroundBlur(to window: NSWindow) {
        guard let app else { return }
        ghostty_set_window_background_blur(app, Unmanaged.passUnretained(window).toOpaque())
    }

    // MARK: - Surface lifecycle

    func newSurface(
        nsView: NSView,
        scaleFactor: Double,
        workingDirectory: String? = nil,
        extraEnv: [String: String] = [:]
    ) -> ghostty_surface_t? {
        guard let app else { return nil }

        var cfg = ghostty_surface_config_new()
        cfg.platform_tag = GHOSTTY_PLATFORM_MACOS
        cfg.platform = ghostty_platform_u(macos: ghostty_platform_macos_s(
            nsview: Unmanaged.passUnretained(nsView).toOpaque()
        ))
        cfg.scale_factor = scaleFactor
        cfg.context = GHOSTTY_SURFACE_CONTEXT_WINDOW
        cfg.userdata = Unmanaged.passUnretained(nsView).toOpaque()

        // Build env vars: defaultEnv + extraEnv + ZDOTDIR hijack.
        var merged = defaultEnv
        for (k, v) in extraEnv { merged[k] = v }

        // ZDOTDIR hijack — make zsh load our shim .zshenv on launch so the
        // bootstrap script can autoload at first prompt without the user
        // editing ~/.zshrc. The shim restores the user's original ZDOTDIR
        // (stashed in IN0_ORIG_ZDOTDIR) so their real config still loads.
        // Skipped if IN0_AGENT_HOOKS_DIR isn't set (we never built the
        // ghostty resources in this build) or the shim is absent.
        if let hooksDir = merged["IN0_AGENT_HOOKS_DIR"] {
            let shimDir = (hooksDir as NSString).appendingPathComponent("zdotdir")
            if FileManager.default.fileExists(atPath: shimDir + "/.zshenv") {
                if let userZdot = ProcessInfo.processInfo.environment["ZDOTDIR"] {
                    merged["IN0_ORIG_ZDOTDIR"] = userZdot
                }
                merged["ZDOTDIR"] = shimDir
            }
        }

        let envEntries = merged.map { (key: $0.key, value: $0.value) }

        // Allocate stable C strings + the env_vars array. Freed at function exit.
        var keyPtrs: [UnsafeMutablePointer<CChar>?] = []
        var valPtrs: [UnsafeMutablePointer<CChar>?] = []
        var envArr = [ghostty_env_var_s](repeating: ghostty_env_var_s(key: nil, value: nil),
                                         count: envEntries.count)
        for (i, entry) in envEntries.enumerated() {
            let kp = strdup(entry.key)
            let vp = strdup(entry.value)
            keyPtrs.append(kp)
            valPtrs.append(vp)
            envArr[i].key = UnsafePointer(kp)
            envArr[i].value = UnsafePointer(vp)
        }
        defer {
            for p in keyPtrs { if let p { free(p) } }
            for p in valPtrs { if let p { free(p) } }
        }

        var surface: ghostty_surface_t?
        envArr.withUnsafeMutableBufferPointer { envBuf in
            cfg.env_vars = envBuf.baseAddress
            cfg.env_var_count = envEntries.count
            if let workingDirectory {
                let arr = ContiguousArray(workingDirectory.utf8CString)
                surface = arr.withUnsafeBufferPointer { wdBuf in
                    cfg.working_directory = wdBuf.baseAddress
                    return ghostty_surface_new(app, &cfg)
                }
            } else {
                surface = ghostty_surface_new(app, &cfg)
            }
        }
        return surface
    }

    func freeSurface(_ surface: ghostty_surface_t) {
        ghostty_surface_free(surface)
    }
}

// MARK: - C callbacks

private func wakeupCallback(_ userdata: UnsafeMutableRawPointer?) {
    DispatchQueue.main.async {
        GhosttyBridge.shared.tick()
    }
}

private func actionCallback(
    _ app: ghostty_app_t?,
    _ target: ghostty_target_s,
    _ action: ghostty_action_s
) -> Bool {
    switch action.tag {
    case GHOSTTY_ACTION_CELL_SIZE:
        let cs = action.action.cell_size
        if target.tag == GHOSTTY_TARGET_SURFACE,
           let surface = target.target.surface,
           let raw = ghostty_surface_userdata(surface) {
            let widthPx = cs.width, heightPx = cs.height
            DispatchQueue.main.async {
                let view = Unmanaged<GhosttyTerminalView>.fromOpaque(raw).takeUnretainedValue()
                let scale = view.window?.backingScaleFactor ?? 2.0
                view.applyCellSize(widthPx: widthPx, heightPx: heightPx, scale: scale)
            }
        }
        return true
    case GHOSTTY_ACTION_SCROLLBAR:
        let sb = action.action.scrollbar
        if target.tag == GHOSTTY_TARGET_SURFACE,
           let surface = target.target.surface,
           let raw = ghostty_surface_userdata(surface) {
            let total = sb.total, offset = sb.offset, length = sb.len
            DispatchQueue.main.async {
                let view = Unmanaged<GhosttyTerminalView>.fromOpaque(raw).takeUnretainedValue()
                view.applyScrollbar(total: total, offset: offset, len: length)
                GhosttyBridge.shared.onScrollbar?(view.terminalId, total, offset, length)
            }
        }
        return true
    case GHOSTTY_ACTION_COLOR_CHANGE:
        let cc = action.action.color_change
        let kind = Int32(cc.kind.rawValue)
        let r = cc.r, g = cc.g, b = cc.b
        DispatchQueue.main.async {
            GhosttyBridge.shared.onColorChange?(kind, r, g, b)
        }
        return true
    case GHOSTTY_ACTION_PWD:
        guard target.tag == GHOSTTY_TARGET_SURFACE,
              let surface = target.target.surface,
              let pwdPtr = action.action.pwd.pwd
        else { return true }
        let pwd = String(cString: pwdPtr)
        // Surface userdata was set to the NSView pointer in newSurface.
        if let raw = ghostty_surface_userdata(surface) {
            let view = Unmanaged<GhosttyTerminalView>.fromOpaque(raw).takeUnretainedValue()
            let terminalId = view.terminalId
            DispatchQueue.main.async {
                GhosttyBridge.shared.onPwdChanged?(terminalId, pwd)
            }
        }
        return true
    default:
        return true
    }
}

private func readClipboardCallback(
    _ userdata: UnsafeMutableRawPointer?,
    _ kind: ghostty_clipboard_e,
    _ state: UnsafeMutableRawPointer?
) -> Bool {
    return false
}

private func confirmReadClipboardCallback(
    _ userdata: UnsafeMutableRawPointer?,
    _ str: UnsafePointer<CChar>?,
    _ state: UnsafeMutableRawPointer?,
    _ request: ghostty_clipboard_request_e
) {
    // no-op for V1
}

private func writeClipboardCallback(
    _ userdata: UnsafeMutableRawPointer?,
    _ kind: ghostty_clipboard_e,
    _ content: UnsafePointer<ghostty_clipboard_content_s>?,
    _ count: Int,
    _ confirm: Bool
) {
    // no-op for V1
}

private func closeSurfaceCallback(
    _ userdata: UnsafeMutableRawPointer?,
    _ processAlive: Bool
) {
    // V1: surface lifetime tracked by SurfaceCache; no-op here.
}
