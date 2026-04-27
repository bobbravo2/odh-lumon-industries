#!/usr/bin/env bats

# Unit tests for preflight.sh logic.
# These tests validate the preflight script's behavior using mocked
# environments. They do NOT require CRC or a real cluster.

SCRIPT="scripts/preflight.sh"

@test "preflight script exists and is executable" {
  [ -x "$SCRIPT" ]
}

@test "preflight script passes shellcheck" {
  run shellcheck --severity=warning "$SCRIPT"
  [ "$status" -eq 0 ]
}

@test "preflight script starts with bash shebang" {
  head -1 "$SCRIPT" | grep -q "#!/usr/bin/env bash"
}

@test "preflight script uses set -euo pipefail" {
  grep -q "set -euo pipefail" "$SCRIPT"
}

@test "preflight checks for macOS" {
  grep -q "uname" "$SCRIPT"
}

@test "preflight checks RAM" {
  grep -q "hw.memsize" "$SCRIPT"
}

@test "preflight checks disk space" {
  grep -q "df -k" "$SCRIPT"
}

@test "preflight checks CPU cores" {
  grep -q "hw.physicalcpu" "$SCRIPT"
}

@test "preflight checks for oc CLI" {
  grep -q "command -v oc" "$SCRIPT"
}

@test "preflight checks for crc CLI" {
  grep -q "command -v crc" "$SCRIPT"
}

@test "preflight checks for pull secret" {
  grep -q "PULL_SECRET_PATH" "$SCRIPT"
}

@test "preflight outputs summary" {
  grep -q "Preflight Summary" "$SCRIPT"
}
