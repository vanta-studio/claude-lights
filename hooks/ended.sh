#!/usr/bin/env bash
#
# Claude Code SessionEnd hook: the session has terminated. Removes this
# session's entry from the status file so it disappears from the menu.
#
# Ungraceful terminations (e.g. force-quitting the terminal) may not fire this
# hook; those are cleaned up by the app's stale-session timeout instead.
#
# Reads the hook payload JSON from stdin and forwards it to update-status.sh.

set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$DIR/update-status.sh" remove
