#!/usr/bin/env bash
# Post-process step run after `xcodegen generate`.
#
# xcodegen has a quirk where it auto-creates a self-named subgroup
# (matching the project directory) and puts Config.xcconfig inside it.
# Xcode GUI then walks the wrong parent during path resolution and reports
# "Unable to open base configuration reference file '…/Config.xcconfig'".
# CLI xcodebuild works because its resolver takes a different path.
#
# This script strips the duplicate group out of project.pbxproj while
# preserving the direct Config.xcconfig reference in the root group.
#
# Why a script and not a project.yml fix: xcodegen ships no option to
# suppress this auto-group, and `fileGroups` doesn't prevent it either —
# only post-processing reliably removes both the group definition and
# the dangling child entry in the root group.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PBX="$ROOT/in0.xcodeproj/project.pbxproj"

[ -f "$PBX" ] || { echo "$PBX missing" >&2; exit 1; }

# Find the group id of the self-named subgroup that only holds
# Config.xcconfig. xcodegen names it after the project directory.
PROJ_DIR_NAME="$(basename "$ROOT")"

# Use python for the surgery — sed across multiline pbxproj blocks is fragile.
python3 <<PY
import re, pathlib, sys

pbx = pathlib.Path("$PBX")
text = pbx.read_text()
dirname = "$PROJ_DIR_NAME"

# Find the bogus group (path = . AND name matches project dir) — capture id.
group_pattern = re.compile(
    r'\t\t([0-9A-F]{24}) /\* ' + re.escape(dirname) + r' \*/ = \{\n'
    r'\t\t\tisa = PBXGroup;\n'
    r'\t\t\tchildren = \(\n'
    r'\t\t\t\t([0-9A-F]{24}) /\* Config\.xcconfig \*/,\n'
    r'\t\t\t\);\n'
    r'\t\t\tname = "' + re.escape(dirname) + r'";\n'
    r'\t\t\tpath = \.;\n'
    r'\t\t\tsourceTree = "<group>";\n'
    r'\t\t\};\n',
    re.MULTILINE,
)
m = group_pattern.search(text)
if not m:
    print("postgen: no bogus group found — nothing to fix")
    sys.exit(0)

group_id = m.group(1)
# Remove the group definition.
text = group_pattern.sub("", text)
# Remove the dangling child entry in whatever parent group references it.
text = re.sub(
    r'\t\t\t\t' + group_id + r' /\* ' + re.escape(dirname) + r' \*/,\n',
    "",
    text,
)

pbx.write_text(text)
print(f"postgen: removed bogus {dirname} group ({group_id})")
PY
