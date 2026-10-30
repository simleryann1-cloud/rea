#!/bin/bash
set -euo pipefail

# Cloud sessions only; on WSL2 or Linux run .claude/rea-env.sh once by hand.
if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
  exit 0
fi

exec "${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "$0")/../.." && pwd)}/.claude/rea-env.sh"
