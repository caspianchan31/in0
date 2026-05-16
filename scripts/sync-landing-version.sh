#!/usr/bin/env bash
#
# sync-landing-version.sh
#
# Keeps `landing-page/index.html`'s download-button version label in sync
# with `Config.xcconfig`'s MARKETING_VERSION. `--check` reports drift
# without modifying anything (used by CI + check-doc-drift). Without
# `--check`, the script rewrites the HTML in place.
#
# The HTML is expected to contain a pinned span like:
#
#   <span data-in0-version>v0.0.1</span>
#
# We rewrite the `vX.Y.Z` portion when MARKETING_VERSION changes.

set -euo pipefail

mode="apply"
case "${1:-}" in
  --check) mode="check" ;;
  "") ;;
  *) echo "usage: $0 [--check]" >&2; exit 2 ;;
esac

here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/.." && pwd)"
config_file="$root/Config.xcconfig"
landing_file="$root/landing-page/index.html"

# Bail silently if there's no landing page yet — the project may not have
# one in the repo we're checking.
if [[ ! -f "$landing_file" ]]; then
  exit 0
fi

version="$(awk -F'= *' '/^MARKETING_VERSION/ {print $2; exit}' "$config_file" | tr -d ' "')"
if [[ -z "$version" ]]; then
  echo "sync-landing-version: MARKETING_VERSION not found in $config_file" >&2
  exit 2
fi

current="$(grep -oE 'data-in0-version[^>]*>v[0-9]+\.[0-9]+\.[0-9]+' "$landing_file" \
  | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' | head -1 || true)"
expected="v$version"

if [[ "$current" == "$expected" ]]; then
  exit 0
fi

if [[ "$mode" == "check" ]]; then
  echo "Landing version drift: HTML shows '${current:-<none>}', Config.xcconfig pins '$expected'." >&2
  echo "  Run ./scripts/sync-landing-version.sh to fix." >&2
  exit 1
fi

# Apply: rewrite every `v<semver>` adjacent to data-in0-version.
sed -E -i.bak \
  "s/(data-in0-version[^>]*>)v[0-9]+\.[0-9]+\.[0-9]+/\\1$expected/g" \
  "$landing_file"
rm -f "$landing_file.bak"
echo "Updated landing-page to $expected."
