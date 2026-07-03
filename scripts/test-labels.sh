#!/usr/bin/env bash
#
# Headless tests for SessionLabels (session naming persistence).

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

xcrun swiftc -o "$WORK/labelstest" \
  "$ROOT/ClaudeLights/SessionLabels.swift" \
  "$ROOT/tests/labels/main.swift"

"$WORK/labelstest"
