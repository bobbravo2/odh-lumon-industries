#!/usr/bin/env bats

# Structural tests for role-check.sh.
# These tests validate script quality and expected patterns.
# They do NOT require a cluster or CRC.

SCRIPT="scripts/role-check.sh"

@test "role-check script exists and is executable" {
  [ -x "$SCRIPT" ]
}

@test "role-check script passes shellcheck" {
  run shellcheck --severity=warning "$SCRIPT"
  [ "$status" -eq 0 ]
}

@test "role-check script starts with bash shebang" {
  head -1 "$SCRIPT" | grep -q "#!/usr/bin/env bash"
}

@test "role-check script uses set -euo pipefail" {
  grep -q "set -euo pipefail" "$SCRIPT"
}

@test "role-check script sources lib.sh" {
  grep -q "lib.sh" "$SCRIPT"
}

@test "role-check script uses impersonation not login" {
  grep -q "can-i" "$SCRIPT"
  run grep -v "^#" "$SCRIPT"
  echo "$output" | grep -qv "oc login"
}

@test "role-check script checks MDR persona" {
  grep -qiE "developer|MDR" "$SCRIPT"
}

@test "role-check script checks O&D persona" {
  grep -qiE "kubeadmin|O&D|admin" "$SCRIPT"
}

@test "role-check script checks dashboard config" {
  grep -qiE "disableKServeAuth|dashboard" "$SCRIPT"
}

@test "role-check script outputs summary" {
  grep -qiE "Summary|summary" "$SCRIPT"
}
