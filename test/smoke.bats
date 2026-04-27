#!/usr/bin/env bats

# Unit tests for smoke.sh structure and script quality.

SCRIPT="scripts/smoke.sh"

@test "smoke script exists and is executable" {
  [ -x "$SCRIPT" ]
}

@test "smoke script passes shellcheck" {
  run shellcheck --severity=warning "$SCRIPT"
  [ "$status" -eq 0 ]
}

@test "smoke script starts with bash shebang" {
  head -1 "$SCRIPT" | grep -q "#!/usr/bin/env bash"
}

@test "smoke script uses set -euo pipefail" {
  grep -q "set -euo pipefail" "$SCRIPT"
}

@test "smoke script checks cluster access" {
  grep -q "oc whoami" "$SCRIPT"
}

@test "smoke script checks operator CSV" {
  grep -q "installedCSV" "$SCRIPT"
}

@test "smoke script checks dashboard route" {
  grep -q "dashboard" "$SCRIPT"
}

@test "smoke script checks workbench images" {
  grep -q "imagestreams" "$SCRIPT"
}

@test "smoke script outputs summary" {
  grep -q "Smoke Validation Summary" "$SCRIPT"
}
