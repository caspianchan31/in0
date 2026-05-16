#!/usr/bin/env bash
# Generate an EdDSA keypair for Sparkle 2 (used to sign appcast entries).
# Run once per app. Public key goes into Info.plist as `SUPublicEDKey`;
# private key stays in your password manager. NEVER commit either.
#
# Requires Sparkle's `generate_keys` tool, shipped in the Sparkle SPM
# checkout under Tools/. Resolve the path the first time you run this.

set -euo pipefail

GEN_KEYS="${GEN_KEYS:-$HOME/.local/sparkle/generate_keys}"
if [ ! -x "$GEN_KEYS" ]; then
  echo "Sparkle generate_keys not found at $GEN_KEYS." >&2
  echo "Download Sparkle from https://github.com/sparkle-project/Sparkle/releases" >&2
  echo "and point GEN_KEYS at its Tools/generate_keys binary." >&2
  exit 1
fi

"$GEN_KEYS"
echo
echo "Add the printed Public Key to in0/Info.plist as SUPublicEDKey."
echo "Save the Private Key in your password manager — Sparkle's appcast"
echo "signing step (./scripts/release.sh) will ask for it."
