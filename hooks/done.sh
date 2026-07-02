#!/usr/bin/env bash
#
# Claude Code Stop hook: the session finished responding and is now waiting for
# a new prompt. Marks this session "done".
#
# Reads the hook payload JSON from stdin and forwards it to update-status.sh.

set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$DIR/update-status.sh" done
