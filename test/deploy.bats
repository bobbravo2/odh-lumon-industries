#!/usr/bin/env bats

# Unit tests for deploy.sh structure and script quality.
# These tests validate the deploy script's structure and patterns.
# They do NOT require a cluster or CRC.

SCRIPT="scripts/deploy.sh"

@test "deploy script exists and is executable" {
  [ -x "$SCRIPT" ]
}

@test "deploy script passes shellcheck" {
  run shellcheck --severity=warning "$SCRIPT"
  [ "$status" -eq 0 ]
}

@test "deploy script starts with bash shebang" {
  head -1 "$SCRIPT" | grep -q "#!/usr/bin/env bash"
}

@test "deploy script uses set -euo pipefail" {
  grep -q "set -euo pipefail" "$SCRIPT"
}

@test "deploy script references config directory" {
  grep -q "CONFIG_DIR" "$SCRIPT"
}

@test "deploy script applies namespace" {
  grep -q "namespace.yaml" "$SCRIPT"
}

@test "deploy script applies operator-group" {
  grep -q "operator-group.yaml" "$SCRIPT"
}

@test "deploy script applies subscription" {
  grep -q "subscription.yaml" "$SCRIPT"
}

@test "deploy script applies DSC" {
  grep -q "dsc.yaml" "$SCRIPT"
}

@test "deploy script waits for operator CSV" {
  grep -q "installedCSV" "$SCRIPT"
}

@test "deploy script checks DSCInitialization readiness" {
  grep -q "DSCInitialization" "$SCRIPT"
}

@test "deploy script checks DataScienceCluster readiness" {
  grep -q "DataScienceCluster" "$SCRIPT"
}
