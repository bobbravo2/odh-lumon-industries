#!/usr/bin/env bash
set -euo pipefail

# One-shot launcher for lumon-industries.
# Runs preflight, starts CRC, deploys ODH, and validates — in that order.
# Stops on the first failure with actionable output.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo ""
echo "🏢 Lumon Industries — Full Deployment Sequence"
echo "   The Board has approved a single-command deployment."
echo ""

bash "${SCRIPT_DIR}/scripts/preflight.sh"
echo ""

# Run crc setup if the daemon is not installed (first run or post-cleanup).
if ! crc status &>/dev/null 2>&1; then
  echo "🔧 CRC needs setup (first run or post-cleanup). Running crc-lifecycle.sh setup..."
  echo ""
  bash "${SCRIPT_DIR}/scripts/crc-lifecycle.sh" setup
  echo ""
fi

bash "${SCRIPT_DIR}/scripts/crc-lifecycle.sh" start
echo ""

bash "${SCRIPT_DIR}/scripts/deploy.sh"
echo ""

bash "${SCRIPT_DIR}/scripts/smoke.sh"
