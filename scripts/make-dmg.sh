#!/usr/bin/env bash
#
# Build a styled "drag to Applications" DMG with a background image, positioned
# icons, and no toolbar — the familiar Mac installer look. Uses only Apple
# tooling (hdiutil + Finder AppleScript).
#
# USAGE:
#   scripts/make-dmg.sh [app_path] [output_dmg]
#
# Defaults: app = build/Release/ClaudeLights.app, output = build/ClaudeLights.dmg
#
# NOTE: The Finder styling step needs permission to control Finder (Automation).
# The first run may prompt for it. If styling is skipped, a plain (but working)
# DMG is still produced.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="${1:-$ROOT/build/Release/ClaudeLights.app}"
OUT="${2:-$ROOT/build/ClaudeLights.dmg}"
BG="$ROOT/scripts/dmg-background.png"
VOL="ClaudeLights"

[ -d "$APP" ] || { echo "error: app not found: $APP" >&2; exit 1; }
[ -f "$BG" ]  || { echo "error: background not found: $BG" >&2; exit 1; }

# --- Stage contents ---
STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT
ditto "$APP" "$STAGING/ClaudeLights.app"
mkdir "$STAGING/.background"
cp "$BG" "$STAGING/.background/background.png"
ln -s /Applications "$STAGING/Applications"

# Detach any stale ClaudeLights volumes so our new one mounts under the exact
# name (otherwise it becomes "ClaudeLights 1" and Finder targets the wrong disk).
for v in /Volumes/"$VOL" /Volumes/"$VOL"\ *; do
  [ -d "$v" ] && hdiutil detach "$v" -force >/dev/null 2>&1 || true
done

# --- Create a read-write DMG so Finder can write its layout (.DS_Store) ---
RW="$(mktemp -u).dmg"
hdiutil create -srcfolder "$STAGING" -volname "$VOL" -fs HFS+ -format UDRW -ov "$RW" >/dev/null

ATTACH="$(hdiutil attach -readwrite -noverify -noautoopen "$RW")"
DEV="$(echo "$ATTACH" | grep '^/dev/' | head -1 | awk '{print $1}')"
MOUNT="$(echo "$ATTACH" | grep -o '/Volumes/.*' | head -1)"
VOLNAME="$(basename "$MOUNT")"
sleep 2

# Sanity: the background must actually be on the mounted volume.
if [ -f "$MOUNT/.background/background.png" ]; then
  echo "background present on volume ✓ ($MOUNT)"
else
  echo "warning: background missing on volume ($MOUNT)" >&2
fi

# --- Style the window via Finder ---
# Icon positions are set first (and guarded) so the drag layout survives even if
# the background step is refused. The background uses an absolute POSIX path,
# which resolves more reliably than a colon path.
osascript <<OSA || echo "warning: Finder styling skipped (Automation permission?)" >&2
tell application "Finder"
  tell disk "$VOLNAME"
    open
    delay 1
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {300, 150, 900, 550}
    set opts to the icon view options of container window
    set arrangement of opts to not arranged
    set icon size of opts to 112
    set text size of opts to 12
    set position of item "ClaudeLights.app" of container window to {150, 190}
    set position of item "Applications" of container window to {450, 190}
    try
      set background picture of opts to POSIX file "$MOUNT/.background/background.png"
    on error errMsg
      log "background set failed: " & errMsg
    end try
    update without registering applications
    delay 2
    close
  end tell
end tell
OSA

sync
hdiutil detach "$DEV" >/dev/null || hdiutil detach "$DEV" -force >/dev/null

# --- Convert to compressed, read-only ---
rm -f "$OUT"
hdiutil convert "$RW" -format UDZO -imagekey zlib-level=9 -o "$OUT" >/dev/null
rm -f "$RW"

echo "Built styled DMG: $OUT"
