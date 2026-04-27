#!/usr/bin/env bash
set -euo pipefail

# Post-deploy smoke validation for lumon-industries.
# Checks operator phase, DSC status, dashboard route, and workbench readiness.

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

echo ""
echo "🏢 Lumon Industries — Deployment Smoke Validation"
echo "   Verifying that the Severed Floor is operational."
echo ""

# ── Cluster Access (CRC context) ──
section "Cluster Access"

use_crc_context
pass "Using CRC context: $(oc config current-context)"
pass "Logged in as: $(oc whoami)"

server="$(oc whoami --show-server 2>/dev/null || echo 'unknown')"
pass "API server: $server"

# ── Operator Status ──
section "Operator Status"

csv_name="$(oc get subscription "$OPERATOR_SUBSCRIPTION_NAME" -n "$OPERATOR_NAMESPACE" \
  -o jsonpath='{.status.installedCSV}' 2>/dev/null || true)"

if [[ -z "$csv_name" ]]; then
  fail "No installed CSV found for $OPERATOR_SUBSCRIPTION_NAME subscription."
else
  csv_phase="$(oc get csv "$csv_name" -n "$OPERATOR_NAMESPACE" \
    -o jsonpath='{.status.phase}' 2>/dev/null || true)"
  if [[ "$csv_phase" == "Succeeded" ]]; then
    pass "Operator CSV '$csv_name': Succeeded"
  else
    fail "Operator CSV '$csv_name': ${csv_phase:-Unknown}"
  fi
fi

operator_pods="$(oc get pods -n "$OPERATOR_NAMESPACE" -l name=rhods-operator \
  --no-headers 2>/dev/null || true)"
if [[ -z "$operator_pods" ]]; then
  operator_pods="$(oc get pods -n "$OPERATOR_NAMESPACE" -l control-plane=controller-manager \
    --no-headers 2>/dev/null || true)"
fi
if [[ -n "$operator_pods" ]]; then
  running="$(echo "$operator_pods" | grep -c Running || true)"
  total="$(echo "$operator_pods" | wc -l | tr -d ' ')"
  if (( running == total )); then
    pass "Operator pods: $running/$total Running"
  else
    warn "Operator pods: $running/$total Running"
  fi
else
  operator_pods_alt="$(oc get pods -n redhat-ods-operator --no-headers 2>/dev/null | head -5 || true)"
  if [[ -n "$operator_pods_alt" ]]; then
    pass "Operator pods found in redhat-ods-operator namespace"
  else
    warn "Could not locate operator pods (may use non-standard namespace or labels)"
  fi
fi

# ── DSCInitialization ──
section "DSCInitialization"

dsci_phase="$(oc get dscinitializations.dscinitialization.opendatahub.io default-dsci \
  -o jsonpath='{.status.phase}' 2>/dev/null || true)"

if [[ "$dsci_phase" == "Ready" ]]; then
  pass "DSCInitialization: Ready"
elif [[ -n "$dsci_phase" ]]; then
  fail "DSCInitialization: $dsci_phase"
else
  fail "DSCInitialization: not found"
fi

# ── DataScienceCluster ──
section "DataScienceCluster"

dsc_phase="$(oc get datascienceclusters.datasciencecluster.opendatahub.io default-dsc \
  -o jsonpath='{.status.phase}' 2>/dev/null || true)"

if [[ "$dsc_phase" == "Ready" ]]; then
  pass "DataScienceCluster: Ready"
elif [[ -n "$dsc_phase" ]]; then
  fail "DataScienceCluster: $dsc_phase"
else
  fail "DataScienceCluster: not found"
fi

components="$(oc get datascienceclusters.datasciencecluster.opendatahub.io default-dsc \
  -o jsonpath='{range .status.conditions[*]}{.type}={.status}{"\n"}{end}' 2>/dev/null || true)"
if [[ -n "$components" ]]; then
  echo "  Component conditions:"
  while IFS= read -r line; do
    cond_type="${line%%=*}"
    cond_status="${line##*=}"
    if [[ "$cond_status" == "True" ]]; then
      echo "    ✅ $cond_type"
    else
      echo "    ❌ $cond_type"
    fi
  done <<< "$components"
fi

# ── Dashboard Route ──
section "Dashboard"

# RHOAI 3.3+ uses a gateway route (data-science-gateway) instead of a direct dashboard route.
dashboard_route="$(oc get route -A -o jsonpath='{range .items[*]}{.spec.host}{"\n"}{end}' 2>/dev/null \
  | grep -m1 'data-science-gateway' || true)"
if [[ -z "$dashboard_route" ]]; then
  dashboard_route="$(oc get route -n "$APPLICATIONS_NAMESPACE" \
    -l app.kubernetes.io/part-of=rhods-dashboard \
    -o jsonpath='{.items[0].spec.host}' 2>/dev/null || true)"
fi
if [[ -z "$dashboard_route" ]]; then
  dashboard_route="$(oc get route -n "$APPLICATIONS_NAMESPACE" \
    -o jsonpath='{.items[0].spec.host}' 2>/dev/null || true)"
fi

if [[ -n "$dashboard_route" ]]; then
  dashboard_url="https://${dashboard_route}"
  http_code="$(curl -skL -o /dev/null -w '%{http_code}' --max-time 10 "$dashboard_url" 2>/dev/null || echo "000")"
  if [[ "$http_code" =~ ^(200|302|403) ]]; then
    pass "Dashboard route: $dashboard_url (HTTP $http_code)"
  else
    warn "Dashboard route: $dashboard_url (HTTP $http_code — may still be starting)"
  fi
else
  fail "Dashboard route not found in namespace $APPLICATIONS_NAMESPACE"
fi

# ── Workbench Images ──
section "Workbench Readiness"

imagestreams="$(oc get imagestreams -n "$APPLICATIONS_NAMESPACE" --no-headers 2>/dev/null | wc -l | tr -d ' ' || echo 0)"
if (( imagestreams > 0 )); then
  pass "Workbench image streams: $imagestreams available"
else
  warn "No workbench image streams found yet (may still be importing)"
fi

# ── Pull Secret Validation ──
section "Pull Secret (registry.redhat.io)"

pull_secret_has_rh="$(python3 -c "
import json, sys
try:
    ps = json.load(open('$HOME/.crc/pull-secret'))
    auths = ps.get('auths', {})
    has_rh = 'registry.redhat.io' in auths
    print('yes' if has_rh else 'no')
except Exception:
    print('error')
" 2>/dev/null || echo 'error')"

if [[ "$pull_secret_has_rh" == "yes" ]]; then
  pass "Pull secret includes registry.redhat.io credentials"
elif [[ "$pull_secret_has_rh" == "no" ]]; then
  fail "Pull secret is MISSING registry.redhat.io credentials."
  echo "         RHOAI images require registry.redhat.io auth."
  echo "         Download an updated pull secret from:"
  echo "         https://console.redhat.com/openshift/install/pull-secret"
else
  warn "Could not parse pull secret at $HOME/.crc/pull-secret"
fi

# ── Summary ──
echo ""
echo "── Smoke Validation Summary ──"
echo "   Passed:   $pass"
echo "   Warnings: $warn"
echo "   Failed:   $fail"
echo ""

if [[ -n "${dashboard_route:-}" ]]; then
  echo "   🖥️  Dashboard: https://${dashboard_route}"
  echo ""
fi

if (( fail > 0 )); then
  echo "❌ Smoke validation FAILED."
  echo "   The Severed Floor has unresolved issues."
  echo "   Check: oc get csv -n $OPERATOR_NAMESPACE"
  echo "   Check: oc get datascienceclusters.datasciencecluster.opendatahub.io default-dsc -o yaml"
  exit 1
elif (( warn > 0 )); then
  echo "⚠️  Smoke validation PASSED with warnings."
  echo "   Some components may still be starting. Re-run in a few minutes."
  exit 0
else
  echo "✅ Smoke validation PASSED."
  echo "   The Severed Floor is fully operational. Praise Kier."
  exit 0
fi
