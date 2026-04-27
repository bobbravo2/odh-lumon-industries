#!/usr/bin/env bash
set -euo pipefail

# RBAC parity matrix for lumon-industries.
# Validates access controls across MDR (developer) and O&D (kubeadmin) personas
# using oc auth can-i impersonation. Never changes context or calls oc login.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

pass=0
fail=0
warn=0

pass() {
  echo "  ✅ $1"
  pass=$(( pass + 1 ))
}

warn() {
  echo "  ⚠️  $1"
  warn=$(( warn + 1 ))
}

fail() {
  echo "  ❌ $1"
  fail=$(( fail + 1 ))
}

section() {
  echo ""
  echo "── $1 ──"
}

expect_allowed() {
  local desc="$1"; shift
  if oc auth can-i "$@" 2>/dev/null | grep -q "yes"; then
    pass "$desc"
  else
    fail "$desc"
  fi
}

expect_denied() {
  local desc="$1"; shift
  if oc auth can-i "$@" 2>/dev/null | grep -q "yes"; then
    fail "$desc (boundary broken)"
  else
    pass "$desc"
  fi
}

echo ""
echo "🏢 Lumon Industries — RBAC Parity Matrix"
echo "   Verifying Severed Floor access controls."
echo ""

use_crc_context
require_openshift

# ── RHOAI Version ──
section "RHOAI Version"

csv_name="$(oc get subscription "$OPERATOR_SUBSCRIPTION_NAME" -n "$OPERATOR_NAMESPACE" \
  -o jsonpath='{.status.installedCSV}' 2>/dev/null || true)"

if [[ -n "$csv_name" ]]; then
  pass "Installed CSV: $csv_name"
else
  warn "Could not detect RHOAI version (no installedCSV on subscription)"
fi

# ── MDR Persona (developer) — Trust Boundaries ──
section "MDR Persona (developer) — Trust Boundaries"

expect_allowed "developer can create projects" \
  create projects --as=developer

expect_denied "developer cannot get nodes" \
  get nodes --as=developer

expect_denied "developer cannot get dscinitializations" \
  get dscinitializations --as=developer

expect_denied "developer cannot list pods in $APPLICATIONS_NAMESPACE" \
  list pods -n "$APPLICATIONS_NAMESPACE" --as=developer

expect_denied "developer cannot list pods in $OPERATOR_NAMESPACE" \
  list pods -n "$OPERATOR_NAMESPACE" --as=developer

expect_denied "developer cannot patch odhdashboardconfigs" \
  patch odhdashboardconfigs -n "$APPLICATIONS_NAMESPACE" --as=developer

# ── O&D Persona (current user) — Operator Stewardship ──
section "O&D Persona (current user) — Operator Stewardship"

expect_allowed "can get csv in $OPERATOR_NAMESPACE" \
  get csv -n "$OPERATOR_NAMESPACE"

expect_allowed "can get datascienceclusters" \
  get datascienceclusters

expect_allowed "can get dscinitializations" \
  get dscinitializations

expect_allowed "can create groups" \
  create groups

expect_allowed "can list namespaces" \
  list namespaces

# ── Dashboard Config — Cross-Persona Parity ──
section "Dashboard Config — Cross-Persona Parity"

dashboard_cfg="odh-dashboard-config"

kserve_auth="$(oc get odhdashboardconfigs "$dashboard_cfg" -n "$APPLICATIONS_NAMESPACE" \
  -o jsonpath='{.spec.dashboardConfig.disableKServeAuth}' 2>/dev/null || true)"

if [[ "$kserve_auth" == "false" ]]; then
  pass "disableKServeAuth: false (auth enforced)"
elif [[ -z "$kserve_auth" ]]; then
  warn "disableKServeAuth: not set (defaulting may vary)"
else
  fail "disableKServeAuth: $kserve_auth (expected false)"
fi

project_sharing="$(oc get odhdashboardconfigs "$dashboard_cfg" -n "$APPLICATIONS_NAMESPACE" \
  -o jsonpath='{.spec.dashboardConfig.disableProjectSharing}' 2>/dev/null || true)"

if [[ "$project_sharing" == "false" ]]; then
  pass "disableProjectSharing: false (sharing enabled)"
elif [[ -z "$project_sharing" ]]; then
  warn "disableProjectSharing: not set (defaulting may vary)"
else
  fail "disableProjectSharing: $project_sharing (expected false)"
fi

allowed_groups="$(oc get odhdashboardconfigs "$dashboard_cfg" -n "$APPLICATIONS_NAMESPACE" \
  -o jsonpath='{.spec.groupsConfig.allowedGroups}' 2>/dev/null || true)"

if [[ "$allowed_groups" == "system:authenticated" ]]; then
  pass "allowedGroups: system:authenticated"
elif [[ -z "$allowed_groups" ]]; then
  warn "allowedGroups: not set"
else
  fail "allowedGroups: $allowed_groups (expected system:authenticated)"
fi

# ── Summary ──
echo ""
echo "── RBAC Parity Summary ──"
echo "   Passed:   $pass"
echo "   Warnings: $warn"
echo "   Failed:   $fail"
echo ""

if (( fail > 0 )); then
  echo "❌ RBAC parity check FAILED."
  echo "   The Severed Floor has access control issues."
  exit 1
elif (( warn > 0 )); then
  echo "⚠️  RBAC parity check PASSED with warnings."
  exit 0
else
  echo "✅ RBAC parity check PASSED."
  echo "   All departments have correct clearance levels."
  exit 0
fi
