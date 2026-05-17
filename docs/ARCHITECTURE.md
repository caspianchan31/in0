# Architecture

> Why in0 is shaped the way it is. This doc explains the implementation
> decisions behind the public codebase.

## TL;DR

```
                 ┌──────────────────────────────────────────────┐
                 │  SwiftUI shell (Sidebar / Settings / cards)   │
                 │  reads stores, calls store mutators           │
                 └────────┬──────────────────────┬───────────────┘
                          │                      │
            @Observable stores             NSViewRepresentable
            (single sources of truth)            │
                          │                      ▼
                          │      ┌──────────────────────────────┐
                          │      │  AppKit core                  │
                          │      │  TabBarView (NSView)          │
                          │      │  SplitPaneView (NSSplitView)  │
                          │      │  GhosttyTerminalView (NSView) │
                          │      └────────────┬─────────────────┘
                          │                   │
                          │                   ▼
                          │      ┌──────────────────────────────┐
                          │      │  GhosttyBridge (singleton)    │
                          │      │  the only place ghostty_*     │
                          │      │  C calls happen               │
                          │      └────────────┬─────────────────┘
                          │                   │
                          ▼                   ▼
                ┌──────────────────────────────────────┐
                │  libghostty (MIT, statically linked)  │
                │  Metal-rendered terminal surfaces     │
                └──────────────────────────────────────┘
```

Hook events (Claude / Codex / OpenCode) flow in *sideways*:

```
Agent CLI  →  bundled wrapper/hook emitter  →  Unix socket  →  HookSocketListener
                                                    │
                                                    ▼
                            HookDispatcher → TerminalStatusStore
                                                    │
                                                    ▼ (re-render)
                                              SwiftUI dot icon
```

---

## Decision 1 — SwiftUI shell + AppKit core (not pure SwiftUI)

**What**: SwiftUI owns Sidebar, Settings, plugin cards, footer, environment injection.
AppKit owns TabBar, NSSplitView, the terminal surface NSView. The bridge is
`NSViewRepresentable`.

**Why**: Two specific things SwiftUI can't do well at the time of writing:

1. **NSSplitView divider drag**. SwiftUI's `HStack` + `.gesture` can't reproduce
   the exact behavior (live resize, snap zones, divider hit-testing) without
   hand-rolling a lot. NSSplitView gives it for free.
2. **ghostty surface frame discipline**. The Metal-backed surface is sensitive
   to layout passes. AppKit's explicit `setFrameSize` + autoresizing mask gives
   pixel-precise control; SwiftUI's deferred layout would race.

**Cost**: Two paradigms in one codebase. Anything that crosses the boundary
goes through a `*Bridge: NSViewRepresentable` (currently `Bridge/TabBridge.swift`).

**What I'd reconsider**: If the user-visible state of the AppKit core ever
became hard to keep in sync with SwiftUI views, I'd push for a deeper unified
state layer (we have one — see Decision 2 — but the boundary surface is still
the place bugs live).

---

## Decision 2 — `@Observable` stores as the only mutable state

**What**: Five stores, each `@MainActor @Observable`, injected into the SwiftUI
environment from `in0App.body`:

| Store | What it owns |
|---|---|
| `WorkspaceStore` | workspaces, project root paths, tabs, `SplitNode` trees, selection |
| `TerminalPwdStore` | per-terminal `pwd` (driven by ghostty's PWD action) |
| `TerminalStatusStore` | per-terminal lifecycle status (driven by hooks) |
| `TerminalSearchStore` | active terminal search UI state and ghostty result counters |
| `WorkspaceMetadataStore` | derived metadata (git branch) — refreshed every 5s |
| `ThemeManager` | active `AppTheme` |
| `PluginStore` | plugin enablement, surfaces, and workspace-card visibility |
| `PluginCardStore` | right-side plugin-card sidebar open/width UI preferences |
| `TodoStore` | workspace-scoped todo items |
| `GitHubScanStore` | local git scan status/results by workspace |
| `AIHistoryStore` | local AI conversation history scan status/results by workspace |

Views never mutate state directly. They call `store.method(...)`. AppKit views
get the stores via the bridge.

**Why**: The alternative (state scattered across NSView subclasses + SwiftUI
@State) made workspace switching ugly in the prototype — every view had to
re-derive its visible state on tab switch. Centralizing in `@Observable`
stores means SwiftUI re-renders happen for free, and AppKit views only need
to subscribe (or pull on bridge update).

**Cost**: All mutations are main-actor. For a terminal multiplexer this is
fine; for high-throughput async work it would be a bottleneck.

---

## Decision 2.1 — Plugin cards live beside the terminal

**What**: Plugins surface primarily as a right-side card sidebar inside the
same workspace. The terminal remains the central AppKit-rendered content;
cards are SwiftUI views outside `TabBridgeContainer`, not children of
`TabContentView` or `SplitPaneView`.

**Why**: Cards are contextual workspace tools. Putting them inside the AppKit
split tree would make them behave like terminal panes and risk corrupting
`SplitNode` persistence. Putting them in a separate dashboard would make users
leave the terminal. A sibling SwiftUI sidebar gives context without touching
terminal surface lifetime, split ratios, or tab selection.

**State split**:

- `PluginStore` owns which plugin cards are visible.
- `PluginCardStore` owns whether the right sidebar is open and its width.
- Card data stays in feature stores (`TodoStore`, `GitHubScanStore`,
  `AIHistoryStore`, `TerminalStatusStore`).

---

## Decision 3 — Surface lifetime ≠ NSView window membership

**What**: A `GhosttyTerminalView` creates its ghostty surface lazily on first
`viewDidMoveToWindow(window != nil)`. It does **not** free the surface when
removed from a window. The cache (`SurfaceCache`) holds the view in memory
across tab switches; surfaces are freed only by explicit `dispose()` from
`reapMissing(aliveIds:)`, driven by `WorkspaceStore` mutations.

**Why**: The natural-looking implementation — "create on attach, free on
detach" — destroys the running shell every time the user switches tabs. Real
terminal multiplexers don't do this. To keep shells alive, view lifetime
must outlast window membership.

**Cost**: Need an explicit reaper. The reaper is driven by store mutations,
which is correct by construction (the only way a terminal id leaves the
workspace is through `closeTerminal` or `closeTab`, both of which trigger
`apply(workspace:)` which calls `reapMissing`).

---

## Decision 4 — `SplitNode` is a structural tree of UUIDs (no surface refs)

**What**:

```swift
indirect enum SplitNode: Codable {
    case terminal(UUID)
    case split(id: UUID, direction: SplitDirection,
               firstRatio: Double,
               first: SplitNode, second: SplitNode)
}
```

The persisted layout is *just structure*. No frames, no positions, no surface
pointers.

**Why**: Frame-based persistence (x, y, w, h) is a multi-display nightmare —
restore on a different monitor and panes land off-screen. Storing only the
tree + ratios means layout is resolution-independent. Surfaces rebind by UUID
at launch.

**Subtlety**: `SplitNode.sameStructure(as:)` lets the renderer skip rebuilds
when only ratios changed (i.e. user is dragging a divider). This avoids
recreating ghostty surfaces on every drag tick.

---

## Decision 5 — Hook protocol over Unix socket (not stdin/stdout, not files)

**What**: Each ghostty surface is launched with two env vars:
`IN0_HOOK_SOCK` (path to a per-bundle Unix socket) and `IN0_TERMINAL_ID`
(UUID of the surface). Agent hooks emit one JSON line per event over the
socket; `HookSocketListener` accepts and dispatches.

**Why each alternative was worse**:

- **stdin/stdout**: would mean intercepting the agent's PTY, breaking the
  whole point of using a terminal emulator.
- **Files in a watched dir** (e.g. inotify-style): inherent races between
  write-end-of-line and read; lose ordering across multiple agents.
- **HTTP**: heavy for what is fundamentally an IPC fire-and-forget.
- **Mach ports**: macOS-only, harder for hook authors to implement.

Unix socket is line-of-sight, ordered, blocking-or-not as you choose, and
trivially scriptable from any language (bash + python, or any socket lib).

**Subtlety — the `needsInput` gate**: Claude Code's `Notification` hook fires
both for genuine permission requests AND as a 60s idle heartbeat. Apply naively
and a finished agent flips to `needsInput` after a minute. So
`TerminalStatusStore.applyNeedsInputGated` only transitions to `.needsInput`
if current status is `.running`. Same gate would be needed for any future
agent with a similar dual-signal design.

---

## Decision 6 — Theme via 8 semantic tokens, no hardcoded colors

**What**: `AppTheme` defines 8 colors (`sidebar`, `canvas`, `foreground`,
`textSecondary`, `border`, `borderStrong`, `accent`, `selection`). Every
view reads from `theme.<token>`. SwiftUI gets `Color`, AppKit gets the
`<token>NS: NSColor` mirror. **Hardcoding `Color(...)` or `NSColor(...)`
anywhere outside `AppTheme.swift` is a regression.**

**Why**: The visual goal is "chrome blends with the terminal". Today
that's "dark-everywhere"; tomorrow it could be "follow ghostty's configured
theme". Keeping a single token surface means the future "follow ghostty
config" implementation is a one-file change to `ThemeManager`, not a sweep
across every view.

---

## Decision 7 — libghostty isolation in two files

**What**: `ghostty_*` C calls happen in **exactly two files**: 
`Ghostty/GhosttyBridge.swift` (app/config/runtime + callbacks) and
`Ghostty/GhosttyTerminalView.swift` (per-surface NSView). Everywhere else
goes through `GhosttyBridge.shared.{newSurface, freeSurface, defaultEnv,
onPwdChanged}` or typed store callbacks such as terminal search state.

**Why**: ghostty's C API is unstable; constraining the contact surface to
two files means the day libghostty rebrands a struct or splits an enum, you
edit two files, not twelve. Also lets the Swift side reason in terms of
clean Swift types (`UUID`, `String`, etc.) without leaking
`ghostty_action_pwd_s` into the rest of the app.

---

## Hard-won facts

1. **zig must be exactly 0.15.2.** ghostty's `build.zig` pins it. brew ships
   0.16, which fails on `Dir.readFileAlloc` signature changes.
2. **macOS filesystem is case-insensitive by default.** Don't reintroduce
   `Vendor/`; it collides with `vendor/`.
3. **Metal toolchain isn't bundled with Xcode 26+.** Run
   `xcodebuild -downloadComponent MetalToolchain` (~700MB).
4. **Linker needs `-lc++ -framework Carbon -framework OSLog`.** libghostty
   pulls in glslang (C++) and TextInputSources (Carbon).
5. **Don't init ghostty in `App.init()`.** `NSApp` is nil there. Move to
   `AppDelegate.applicationWillFinishLaunching`.
6. **`ghostty_init(argc, argv)` must run before `ghostty_config_new()`.**
   Otherwise SIGSEGV at `ghostty_config_new+36`.

---

## Current product boundaries

- **Settings exists and writes a ghostty-style override config.** The
  Settings scene is SwiftUI; the file writer preserves comments, blanks, and
  unknown keys. Debounced writes trigger libghostty config reload, chrome
  theme refresh, and Quick Actions refresh.
- **i18n exists for the primary UI surface.** `LanguageStore`,
  `Localizable.xcstrings`, and `L10n` keep SwiftUI and AppKit text in sync.
- **Sparkle is implemented behind a stub-friendly bridge.** The UI and state
  machine are present; the SPM dependency/feed/public key must be enabled for
  a release build.
- **Mobile companion remains out of scope.** in0's differentiator remains
  desktop agent visibility.
