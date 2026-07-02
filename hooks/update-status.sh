#!/usr/bin/env bash
#
# Merge the current Claude Code session's status into the shared status file.
#
# Usage: update-status.sh <state>
#   <state> is one of: working | done | needs_input
#
# The Claude Code hook payload is read as JSON from stdin. Only the entry for
# this session's `session_id` is updated; all other sessions in the file are
# left untouched (the file is never overwritten wholesale).
#
# Override the status file location with CLAUDELIGHTS_STATUS_FILE if desired.

set -euo pipefail

STATE="${1:?usage: update-status.sh <working|resume|compacting|needs_input|done|remove>}"
STATUS_FILE="${CLAUDELIGHTS_STATUS_FILE:-$HOME/.claude/claudelights-status.json}"

# jq is required to parse the hook payload and merge the entry safely.
if ! command -v jq >/dev/null 2>&1; then
  echo "claudelights: jq is required but not installed" >&2
  exit 0
fi

# Read the entire hook payload from stdin.
PAYLOAD="$(cat)"

# Extract the fields we care about. `// empty` yields an empty string if absent.
SESSION_ID="$(printf '%s' "$PAYLOAD" | jq -r '.session_id // empty')"
CWD="$(printf '%s' "$PAYLOAD" | jq -r '.cwd // empty')"

# Without a session id there is nothing meaningful to record.
if [ -z "$SESSION_ID" ]; then
  exit 0
fi

# SessionEnd: remove this session's entry entirely and stop.
if [ "$STATE" = "remove" ]; then
  [ -f "$STATUS_FILE" ] || exit 0
  jq -e . "$STATUS_FILE" >/dev/null 2>&1 || exit 0
  TMP="$(mktemp "${STATUS_FILE}.XXXXXX")"
  trap 'rm -f "$TMP"' EXIT
  jq --arg sid "$SESSION_ID" 'del(.[$sid])' "$STATUS_FILE" > "$TMP"
  mv -f "$TMP" "$STATUS_FILE"
  trap - EXIT
  exit 0
fi

# Derive a friendly project name from the working directory, if provided.
PROJECT=""
if [ -n "$CWD" ]; then
  PROJECT="$(basename "$CWD")"
fi

# Capture which terminal the session runs in (best effort). TERM_PROGRAM is set
# by most terminals (Apple_Terminal, iTerm.app, ghostty, WezTerm, ...). Stored
# for display and to pick the right terminal app when focusing.
TERM_PROG="${TERM_PROGRAM:-}"

# Best-effort controlling terminal of this hook, inherited from the session
# process (e.g. "ttys003"). Lets the app focus the exact terminal window/tab.
TTY_NAME="$(ps -o tty= -p $$ 2>/dev/null | tr -d ' ')"
case "$TTY_NAME" in
  "" | "?" | "??") TTY_NAME="" ;;
esac

# UTC timestamp in a format the app decodes with .iso8601 (no fractions).
TIMESTAMP="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

mkdir -p "$(dirname "$STATUS_FILE")"

# Start from the existing content, falling back to an empty object. If the file
# is missing or corrupt, treat it as empty rather than failing the hook.
if [ -f "$STATUS_FILE" ] && jq -e . "$STATUS_FILE" >/dev/null 2>&1; then
  BASE="$(cat "$STATUS_FILE")"
else
  BASE="{}"
fi

# --- Active-time accounting (excludes time spent waiting for the user) ---
#
# We track two fields per session:
#   started         ISO time the CURRENT active stretch began, or null if paused
#   active_seconds  total active seconds accumulated from finished stretches
#
# The app shows a live timer (active_seconds + now - started) while active, and a
# frozen total (active_seconds) while paused (needs_input) or done. Modes:
#   working    new turn  -> reset accumulator, start stretch
#   resume     PostToolUse (stored as "working") -> resume if paused, else keep
#   compacting active continuation
#   needs_input / done -> accumulate current stretch, pause (started = null)
EX_STARTED="$(printf '%s' "$BASE" | jq -r --arg s "$SESSION_ID" '.[$s].started // empty')"
EX_ACTIVE="$(printf '%s' "$BASE" | jq -r --arg s "$SESSION_ID" '.[$s].active_seconds // 0')"
NOW_EPOCH="$(date -u +%s)"
iso_to_epoch() { date -j -u -f "%Y-%m-%dT%H:%M:%SZ" "$1" +%s 2>/dev/null || echo ""; }

STORED_STATE="$STATE"
STARTED=""              # empty => JSON null (paused)
ACTIVE="$EX_ACTIVE"

case "$STATE" in
  working)               # fresh turn: reset the accumulator
    ACTIVE=0
    STARTED="$TIMESTAMP"
    ;;
  resume)                # continue working; resume the clock if it was paused
    STORED_STATE="working"
    if [ -n "$EX_STARTED" ]; then STARTED="$EX_STARTED"; else STARTED="$TIMESTAMP"; fi
    ;;
  compacting)            # active continuation
    if [ -n "$EX_STARTED" ]; then STARTED="$EX_STARTED"; else STARTED="$TIMESTAMP"; fi
    ;;
  needs_input | done)    # pause / finish: bank the current stretch, stop the clock
    if [ -n "$EX_STARTED" ]; then
      SE="$(iso_to_epoch "$EX_STARTED")"
      [ -n "$SE" ] && ACTIVE="$(( EX_ACTIVE + (NOW_EPOCH - SE) ))"
    fi
    STARTED=""
    ;;
esac

# Write to a temp file in the same directory, then atomically move it into place
# so the app (and other hooks) never observe a half-written file.
TMP="$(mktemp "${STATUS_FILE}.XXXXXX")"
trap 'rm -f "$TMP"' EXIT

printf '%s' "$BASE" | jq \
  --arg sid "$SESSION_ID" \
  --arg state "$STORED_STATE" \
  --arg project "$PROJECT" \
  --arg ts "$TIMESTAMP" \
  --arg term "$TERM_PROG" \
  --arg tty "$TTY_NAME" \
  --arg started "$STARTED" \
  --argjson active "$ACTIVE" \
  '.[$sid] = {
      state: $state,
      session_id: $sid,
      project: (if $project == "" then null else $project end),
      term: (if $term == "" then null else $term end),
      tty: (if $tty == "" then null else $tty end),
      active_seconds: $active,
      started: (if $started == "" then null else $started end),
      timestamp: $ts
   }' > "$TMP"

mv -f "$TMP" "$STATUS_FILE"
trap - EXIT
