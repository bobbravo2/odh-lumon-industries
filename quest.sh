#!/usr/bin/env bash
set -euo pipefail

# Entrypoint for the RBAC quest runner.
# Checks for the rich dependency and invokes the Python quest script.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
QUEST="${SCRIPT_DIR}/scripts/rbac-quest.py"

# Use the repo venv if it exists, otherwise fall back to system Python.
if [[ -f "${SCRIPT_DIR}/.venv/bin/activate" ]]; then
  # shellcheck source=/dev/null
  source "${SCRIPT_DIR}/.venv/bin/activate"
fi

if ! python3 -c "import rich" 2>/dev/null; then
  echo "❌ The 'rich' Python package is required but not installed."
  echo ""
  echo "   Install options:"
  echo "     pip install -r requirements.txt"
  echo "     uv pip install -r requirements.txt"
  echo ""
  echo "   Or create a venv first:"
  echo "     python3 -m venv .venv && source .venv/bin/activate"
  echo "     pip install -r requirements.txt"
  exit 1
fi

exec python3 "$QUEST" "$@"
