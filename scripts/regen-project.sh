#!/usr/bin/env bash
# Wraps `xcodegen generate` with the post-process step that strips the
# duplicate self-named subgroup it adds for Config.xcconfig (see
# postgen-fix-xcconfig.sh for details). Use this instead of calling
# xcodegen directly so the Xcode GUI never sees the broken pbxproj.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

xcodegen generate
./scripts/postgen-fix-xcconfig.sh
