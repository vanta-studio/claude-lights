#!/usr/bin/env bash
#
# Claude Code PreCompact hook: the session is compacting its conversation
# context. Marks this session "compacting".
#
# Reads the hook payload JSON from stdin and forwards it to update-status.sh.

set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$DIR/update-status.sh" compacting
