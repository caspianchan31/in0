<div align="right">
  <strong>English</strong> | <a href="README.zh-CN.md">简体中文</a>
</div>

<div align="center">
  <h1>in0</h1>
  <p>
    <em>A macOS terminal that knows what your agent is doing.</em>
  </p>
  <p>
    <a href="https://github.com/caspianchan31/in0/blob/main/LICENSE"><img alt="License" src="https://img.shields.io/badge/license-Source--Available-blue?style=flat-square" /></a>
    <img alt="Platform" src="https://img.shields.io/badge/platform-macOS%2014%2B-lightgrey?style=flat-square" />
    <img alt="Swift" src="https://img.shields.io/badge/Swift-5.10-orange?style=flat-square&logo=swift&logoColor=white" />
    <a href="https://github.com/caspianchan31/in0/commits/main"><img alt="Last commit" src="https://img.shields.io/github/last-commit/caspianchan31/in0?style=flat-square" /></a>
  </p>
</div>

<p align="center">
  in0 is a native macOS terminal multiplexer with workspaces, tabs, and split panes — built around a single deliberate idea: <strong>at any moment, you should know whether each of your AI coding agents is running, idle, waiting on you, or done</strong>. Powered by <a href="https://ghostty.org">libghostty</a>, rendered with Metal, written in Swift / SwiftUI / AppKit.
</p>

![in0 screenshot](images/screenshot.png)

## Features

- **Workspaces → Tabs → Splits** — Group terminals by project. Each workspace owns its tabs; each tab is a binary split tree you can cut horizontally or vertically. Switching tabs never kills your shell.
- **Live agent status in the sidebar** — A colored dot per workspace shows whether your Claude Code, Codex, or OpenCode session is *running*, *idle*, *waiting on input*, or *finished*. Driven by a simple Unix-socket hook protocol.
- **Theme-aware chrome and settings** — Semantic tokens drive the chrome, Settings writes a ghostty-style override config, and the sidebar/tab bar can follow the terminal background live.
- **Layout persistence** — Workspaces, tabs, split tree, and per-terminal `pwd` survive restart. Surfaces rebind by UUID; nothing depends on screen coordinates.
- **No leaked frames between paradigms** — SwiftUI owns the outer shell; AppKit owns NSSplitView and the terminal surface. The boundary is one `NSViewRepresentable` per surface. See [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) for why.
- **Source-available** — read the source, build it locally, run it for personal or commercial work. See [`LICENSE`](LICENSE) for the precise terms.

## System Requirements

- macOS 14.0 or later
- Apple Silicon strongly recommended
- Xcode 26+ with Metal toolchain (auto-fetched on first build)

## Getting Started

> in0 is built from source — there are no signed binary releases yet.

### 1. Toolchain

zig **0.15.2** is required (Homebrew's `zig` is 0.16, which doesn't compile ghostty):

```bash
mkdir -p ~/.local/zig
curl -fsSL https://ziglang.org/download/0.15.2/zig-aarch64-macos-0.15.2.tar.xz \
  | tar xJ -C ~/.local/zig --strip-components=1
brew install xcodegen gettext
xcodebuild -downloadComponent MetalToolchain   # ~700MB, one-time
```

### 2. Build libghostty

```bash
./scripts/build-vendor.sh
```

First run takes 30–60 minutes (clones ghostty source to `/tmp/ghostty-src` and builds a static library). Subsequent runs reuse the checkout.

### 3. Build & launch the app

```bash
./scripts/regen-project.sh
xcodebuild -project in0.xcodeproj -scheme in0 -configuration Debug build
open $(xcodebuild -project in0.xcodeproj -scheme in0 -configuration Debug \
       -showBuildSettings | awk -F' = ' '/CONFIGURATION_BUILD_DIR/ {print $2; exit}')/in0.app
```

### 4. Wire up an agent (optional)

Agent status is wired through bundled wrappers in `Resources/agent-hooks/`. zsh sessions launched from in0 auto-bootstrap through the app's `ZDOTDIR` shim; bash/fish users can copy the rc snippet from **Agents → Copy … rc Snippet**. Codex still requires enabling its experimental hook flag in `~/.codex/config.toml`.

## Background

in0 is a source-available terminal app built around the parts that matter most for this project: libghostty integration, SwiftUI ↔ AppKit boundaries, persistent tab/split state, and live coding-agent visibility.

This is a **personal portfolio project**, not a product. I'm not actively soliciting contributions; if you find something useful here, fork it (see [`LICENSE`](LICENSE) for fork terms).

## License

[`IN0 Source-Available License`](LICENSE) — read, build, and run for personal or commercial work; don't redistribute, repackage, or train models on the source. ghostty itself remains MIT.
