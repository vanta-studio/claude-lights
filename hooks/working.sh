#!/usr/bin/env bash
#
# Claude Code UserPromptSubmit hook: the session just received a prompt and is
# now working. Marks this session "working".
#
# Reads the hook payload JSON from stdin and forwards it to update-status.sh.

set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$DIR/update-status.sh" working
