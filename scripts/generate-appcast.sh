#!/usr/bin/env bash
# Generate / update appcast.xml from the GitHub Releases for this repo.
# Sparkle's `generate_appcast` tool reads a directory of release artifacts
# and produces the XML feed; we point it at a freshly-downloaded folder.

set -euo pipefail

if [ $# -lt 2 ]; then
  echo "usage: $0 <version> <sparkle_signature>" >&2
  exit 1
fi
VERSION="$1"
SIG="$2"

: "${GH_RELEASE_REPO:?GH_RELEASE_REPO is required}"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FEED="$ROOT/dist/appcast.xml"
WORK="$ROOT/dist/appcast-work"
mkdir -p "$WORK"

echo "→ Pull all DMGs from GitHub Releases"
gh release download --repo "$GH_RELEASE_REPO" --pattern '*.dmg' --dir "$WORK" --clobber || true

GEN_APPCAST="${GEN_APPCAST:-$HOME/.local/sparkle/generate_appcast}"
if [ ! -x "$GEN_APPCAST" ]; then
  echo "Sparkle generate_appcast not found at $GEN_APPCAST." >&2
  exit 1
fi

echo "→ generate_appcast"
"$GEN_APPCAST" \
  --download-url-prefix "https://github.com/$GH_RELEASE_REPO/releases/download/v$VERSION/" \
  -o "$FEED" \
  "$WORK"

echo "Done. Commit $FEED and host it at the SUFeedURL in Info.plist."
