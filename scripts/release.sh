#!/usr/bin/env bash
# Build, sign, notarize, package, and publish a versioned in0 release.
#
# Usage:  ./scripts/release.sh <version>
# Example: ./scripts/release.sh 1.0.0
#
# Required env (set in your shell or a release.env loaded above this script):
#   APPLE_ID            iCloud account holding the Developer ID cert
#   APPLE_TEAM_ID       10-char team id (e.g. AB12CD34EF)
#   APPLE_APP_PASSWORD  app-specific password from appleid.apple.com
#   DEVELOPER_ID        full identity, e.g. "Developer ID Application: Jane Doe (AB12CD34EF)"
#   SPARKLE_PRIVATE_KEY EdDSA private key (base64) saved from sparkle-keygen.sh
#   GH_RELEASE_REPO     owner/repo for `gh release create`

set -euo pipefail

if [ $# -lt 1 ]; then
  echo "usage: $0 <version>" >&2
  exit 1
fi
VERSION="$1"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

: "${APPLE_ID:?APPLE_ID is required}"
: "${APPLE_TEAM_ID:?APPLE_TEAM_ID is required}"
: "${APPLE_APP_PASSWORD:?APPLE_APP_PASSWORD is required}"
: "${DEVELOPER_ID:?DEVELOPER_ID is required}"
: "${SPARKLE_PRIVATE_KEY:?SPARKLE_PRIVATE_KEY is required}"
: "${GH_RELEASE_REPO:?GH_RELEASE_REPO is required}"

OUT="$ROOT/dist/$VERSION"
mkdir -p "$OUT"

echo "→ Build Release"
xcodebuild \
  -project in0.xcodeproj \
  -scheme in0 \
  -configuration Release \
  -derivedDataPath "$OUT/derived" \
  MARKETING_VERSION="$VERSION" \
  CURRENT_PROJECT_VERSION="$VERSION" \
  build

APP="$OUT/derived/Build/Products/Release/in0.app"

echo "→ Sign"
./scripts/sign-and-notarize.sh "$APP"

echo "→ DMG"
DMG="$OUT/in0-$VERSION.dmg"
./scripts/build-dmg.sh "$APP" "$DMG"

echo "→ Sparkle sign"
SIG=$(echo -n "$SPARKLE_PRIVATE_KEY" | \
  "$HOME/.local/sparkle/sign_update" -k - "$DMG")
echo "Sparkle signature: $SIG"

echo "→ GitHub release"
gh release create "v$VERSION" "$DMG" \
  --repo "$GH_RELEASE_REPO" \
  --title "in0 $VERSION" \
  --generate-notes

echo "→ Regenerate appcast"
./scripts/generate-appcast.sh "$VERSION" "$SIG"

echo "Done. Don't forget to commit the updated appcast.xml."
