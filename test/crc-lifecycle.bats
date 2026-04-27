#!/usr/bin/env bats

# Unit tests for crc-lifecycle.sh structure and script quality.

SCRIPT="scripts/crc-lifecycle.sh"

@test "crc-lifecycle script exists and is executable" {
  [ -x "$SCRIPT" ]
}

@test "crc-lifecycle script passes shellcheck" {
  run shellcheck --severity=warning "$SCRIPT"
  [ "$status" -eq 0 ]
}

@test "crc-lifecycle script starts with bash shebang" {
  head -1 "$SCRIPT" | grep -q "#!/usr/bin/env bash"
}

@test "crc-lifecycle script uses set -euo pipefail" {
  grep -q "set -euo pipefail" "$SCRIPT"
}

@test "crc-lifecycle supports setup command" {
  grep -q "cmd_setup" "$SCRIPT"
}

@test "crc-lifecycle supports start command" {
  grep -q "cmd_start" "$SCRIPT"
}

@test "crc-lifecycle supports stop command" {
  grep -q "cmd_stop" "$SCRIPT"
}

@test "crc-lifecycle supports delete command" {
  grep -q "cmd_delete" "$SCRIPT"
}

@test "crc-lifecycle supports status command" {
  grep -q "cmd_status" "$SCRIPT"
}

@test "crc-lifecycle supports login command" {
  grep -q "cmd_login" "$SCRIPT"
}

@test "crc-lifecycle configures memory" {
  grep -q "CRC_MEMORY" "$SCRIPT"
}

@test "crc-lifecycle configures CPUs" {
  grep -q "CRC_CPUS" "$SCRIPT"
}

@test "crc-lifecycle references pull secret path" {
  grep -q "PULL_SECRET_PATH" "$SCRIPT"
}
