#!/usr/bin/env bash
#
# Generate and sign the Sparkle appcast for the DMGs in a directory, using
# Sparkle's `generate_appcast` tool. The tool signs each update with the private
# EdDSA key created by `generate_keys` (stored in your login keychain) and writes
# an appcast.xml next to the updates.
#
# Then upload BOTH the .dmg and the produced appcast.xml as assets of a GitHub
# Release. The app's SUFeedURL points at
# https://github.com/OWNER/claude-lights/releases/latest/download/appcast.xml
#
# USAGE:
#   scripts/sparkle-appcast.sh [updates_dir]
#
# updates_dir defaults to ./build (where release.sh writes ClaudeLights.dmg).
#
# Set SPARKLE_BIN to the folder containing generate_appcast if it can't be found
# automatically (Sparkle ships it in its release tarball's bin/ directory, and
# SPM places it under DerivedData/.../SourcePackages/artifacts/sparkle/…/bin).

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
UPDATES_DIR="${1:-$ROOT/build}"

find_tool() {
  if [ -n "${SPARKLE_BIN:-}" ] && [ -x "$SPARKLE_BIN/generate_appcast" ]; then
    echo "$SPARKLE_BIN/generate_appcast"; return 0
  fi
  if command -v generate_appcast >/dev/null 2>&1; then
    command -v generate_appcast; return 0
  fi
  # Best-effort search in Xcode's SPM artifacts.
  local hit
  hit="$(find "$HOME/Library/Developer/Xcode/DerivedData" \
          -type f -name generate_appcast -path '*artifacts*' 2>/dev/null | head -1 || true)"
  if [ -n "$hit" ]; then echo "$hit"; return 0; fi
  return 1
}

TOOL="$(find_tool)" || {
  echo "error: generate_appcast not found." >&2
  echo "Install Sparkle's tools or set SPARKLE_BIN=/path/to/Sparkle/bin" >&2
  echo "Download: https://github.com/sparkle-project/Sparkle/releases" >&2
  exit 1
}

if [ ! -d "$UPDATES_DIR" ]; then
  echo "error: updates dir not found: $UPDATES_DIR" >&2
  exit 1
fi

echo "Using: $TOOL"
echo "Signing updates in: $UPDATES_DIR"
"$TOOL" "$UPDATES_DIR"

echo ""
echo "Wrote $UPDATES_DIR/appcast.xml"
echo "Next: create a GitHub Release and upload both the .dmg and appcast.xml as assets."
