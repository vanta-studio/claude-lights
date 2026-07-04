#!/usr/bin/env bash
#
# Headless tests for SessionStatus background-task decoding and summary
# formatting. Compiles Models.swift with the test driver.
#
# Usage: scripts/test-background-model.sh

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

xcrun swiftc -o "$WORK/bgtest" \
  "$ROOT/ClaudeLights/Models.swift" \
  "$ROOT/tests/background/main.swift"

"$WORK/bgtest"
