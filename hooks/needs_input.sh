#!/usr/bin/env bash
#
# Claude Code Notification hook (matcher: idle_prompt|permission_prompt|
# agent_needs_input|elicitation_dialog) or PreToolUse hook (matcher:
# AskUserQuestion): the session needs the user's attention — a permission
# request, a question, or it has been idle waiting for input. Marks this
# session "needs_input".
#
# Reads the hook payload JSON from stdin and forwards it to update-status.sh.

set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$DIR/update-status.sh" needs_input
