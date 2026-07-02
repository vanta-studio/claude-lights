#!/usr/bin/env bash
#
# Claude Code PostToolUse hook: a tool just ran, so the session is actively
# working again (e.g. after you approved a permission prompt). Resumes the work
# timer — if it was paused waiting for input, the clock starts ticking again;
# otherwise it just keeps running. Stored state is "working".
#
# Reads the hook payload JSON from stdin and forwards it to update-status.sh.

set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$DIR/update-status.sh" resume
