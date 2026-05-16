#!/usr/bin/env bash
# Build libghostty.a from source.
#
# Requires zig 0.15.2 EXACTLY. Ghostty's build.zig pins requireZig to 0.15.2;
# zig 0.16+ changes Dir.readFileAlloc signatures and the build fails. Homebrew
# currently ships 0.16, so install via tarball:
#
#   curl -fsSL https://ziglang.org/download/0.15.2/zig-aarch64-macos-0.15.2.tar.xz \
#     | tar xJ -C ~/.local/zig --strip-components=1
#
# Run once before opening the Xcode project, and again whenever you want to pull
# a fresh ghostty.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Ghostty source location. Default: clone to /tmp so the public repo stays
# self-contained (we don't vendor the upstream tree). Override by setting
# GHOSTTY_SRC=/path/to/your/checkout.
GHOSTTY_SRC="${GHOSTTY_SRC:-/tmp/ghostty-src}"
GHOSTTY_REPO="${GHOSTTY_REPO:-https://github.com/ghostty-org/ghostty.git}"

if ! command -v zig >/dev/null 2>&1; then
  if [ -x "$HOME/.local/zig/zig" ]; then
    export PATH="$HOME/.local/zig:$PATH"
  else
    echo "ERROR: zig not in PATH and ~/.local/zig/zig not found." >&2
    echo "Install zig 0.15.2 — see header comment in this file." >&2
    exit 1
  fi
fi

ZIG_VER="$(zig version)"
case "$ZIG_VER" in
  0.15.2) ;;
  *)
    echo "ERROR: zig $ZIG_VER detected; ghostty requires exactly 0.15.2." >&2
    exit 1
    ;;
esac

# Auto-clone ghostty source if missing.
if [ ! -d "$GHOSTTY_SRC/.git" ] && [ ! -f "$GHOSTTY_SRC/build.zig" ]; then
  echo ">>> cloning $GHOSTTY_REPO → $GHOSTTY_SRC (shallow)"
  mkdir -p "$(dirname "$GHOSTTY_SRC")"
  git clone --depth 1 "$GHOSTTY_REPO" "$GHOSTTY_SRC"
fi

cd "$GHOSTTY_SRC"
echo ">>> building libghostty (ReleaseFast, no .app)..."
zig build -Doptimize=ReleaseFast -Demit-macos-app=false

OUT_INC="$PROJECT_DIR/vendor/ghostty/include"
OUT_LIB="$PROJECT_DIR/vendor/ghostty/lib"
OUT_SHARE="$PROJECT_DIR/vendor/ghostty/share"
mkdir -p "$OUT_INC" "$OUT_LIB" "$OUT_SHARE"

XCFW="$GHOSTTY_SRC/macos/GhosttyKit.xcframework/macos-arm64_x86_64"
if [ -f "$XCFW/ghostty-internal.a" ]; then
  cp "$XCFW/Headers/ghostty.h" "$OUT_INC/"
  cp "$XCFW/ghostty-internal.a" "$OUT_LIB/libghostty.a"
elif [ -f "$GHOSTTY_SRC/zig-out/lib/libghostty.a" ]; then
  cp "$GHOSTTY_SRC/zig-out/include/ghostty.h" "$OUT_INC/"
  cp "$GHOSTTY_SRC/zig-out/lib/libghostty.a" "$OUT_LIB/libghostty.a"
else
  echo "ERROR: libghostty.a not produced — checked GhosttyKit.xcframework and zig-out/lib/" >&2
  exit 1
fi

if [ -d "$GHOSTTY_SRC/zig-out/share/ghostty" ]; then
  cp -R "$GHOSTTY_SRC/zig-out/share/ghostty/" "$OUT_SHARE/"
fi

echo ">>> done"
ls -la "$OUT_INC" "$OUT_LIB"
