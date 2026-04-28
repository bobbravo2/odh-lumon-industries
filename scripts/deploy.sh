#!/usr/bin/env bash
set -euo pipefail

# Main deploy orchestrator for lumon-industries.
# Applies OLM CRs in the correct order, waits for operator readiness,
# and deploys the DataScienceCluster with all components Managed.
#
# Uses the RHOAI downstream operator (rhods-operator) because it ships
# multi-arch images including arm64 for Apple Silicon.
# Images pull from registry.redhat.io — your pull secret must include
# those credentials. CRC injects the pull secret during 'crc start'.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="${SCRIPT_DIR}/../config"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

OPERATOR_POLL_INTERVAL=15
OPERATOR_POLL_TIMEOUT=600   # 10 minutes for operator to reach Succeeded
DSC_POLL_TIMEOUT=900        # 15 minutes for DSC reconciliation

echo ""
echo "🏢 Lumon Industries — Deploying the Severed Floor Product Stack"
echo "   Applying the Board-approved OLM install flow (RHOAI downstream)."
echo ""

# ── Verify cluster access ──
echo "── Verifying cluster access (CRC context) ──"
use_crc_context
require_openshift
require_olm
echo "  ✅ Logged in as $(oc whoami) on $(oc whoami --show-server)"
echo ""

# ── Step 1: Namespace ──
echo "── Step 1: Ensuring applications namespace ──"
if oc get namespace "$APPLICATIONS_NAMESPACE" &>/dev/null 2>&1; then
  echo "  ✅ Namespace '$APPLICATIONS_NAMESPACE' already exists."
else
  oc apply -f "${CONFIG_DIR}/namespace.yaml"
  echo "  ✅ Namespace '$APPLICATIONS_NAMESPACE' created."
fi
echo ""

# ── Step 2: OperatorGroup ──
echo "── Step 2: Ensuring OperatorGroup ──"
existing_og_count="$(oc get operatorgroup -n "$OPERATOR_NAMESPACE" --no-headers 2>/dev/null | wc -l | tr -d ' ')"
if (( existing_og_count > 0 )); then
  existing_og="$(oc get operatorgroup -n "$OPERATOR_NAMESPACE" --no-headers 2>/dev/null | awk '{print $1}' | head -1)"
  echo "  ✅ OperatorGroup already exists in $OPERATOR_NAMESPACE ($existing_og). Skipping."
else
  oc apply -f "${CONFIG_DIR}/operator-group.yaml"
  echo "  ✅ OperatorGroup created."
fi
echo ""

# ── Step 3: Subscription ──
echo "── Step 3: Applying OLM Subscription ($OPERATOR_SUBSCRIPTION_NAME) ──"
if oc get subscription -n "$OPERATOR_NAMESPACE" "$OPERATOR_SUBSCRIPTION_NAME" &>/dev/null 2>&1; then
  echo "  ✅ Subscription '$OPERATOR_SUBSCRIPTION_NAME' already exists."
else
  oc apply -f "${CONFIG_DIR}/subscription.yaml"
  echo "  ✅ Subscription '$OPERATOR_SUBSCRIPTION_NAME' created."
  echo "     Images pull from registry.redhat.io (authenticated via your pull secret)."
fi
echo ""

# ── Step 4: Wait for operator ──
echo "── Step 4: Waiting for operator to reach 'Succeeded' phase ──"
elapsed=0
operator_ready=false
while (( elapsed < OPERATOR_POLL_TIMEOUT )); do
  csv_name="$(oc get subscription "$OPERATOR_SUBSCRIPTION_NAME" -n "$OPERATOR_NAMESPACE" \
    -o jsonpath='{.status.installedCSV}' 2>/dev/null || true)"

  if [[ -n "$csv_name" ]]; then
    phase="$(oc get csv "$csv_name" -n "$OPERATOR_NAMESPACE" \
      -o jsonpath='{.status.phase}' 2>/dev/null || true)"
    if [[ "$phase" == "Succeeded" ]]; then
      echo "  ✅ Operator CSV '$csv_name' phase: Succeeded"
      operator_ready=true
      break
    fi
    echo "  ⏳ CSV '$csv_name' phase: ${phase:-Pending} (${elapsed}s / ${OPERATOR_POLL_TIMEOUT}s)"
  else
    echo "  ⏳ Waiting for CSV to be created... (${elapsed}s / ${OPERATOR_POLL_TIMEOUT}s)"
  fi

  sleep "$OPERATOR_POLL_INTERVAL"
  elapsed=$(( elapsed + OPERATOR_POLL_INTERVAL ))
done

if [[ "$operator_ready" != "true" ]]; then
  echo "❌ Operator did not reach Succeeded within ${OPERATOR_POLL_TIMEOUT}s."
  echo "   Check: oc get csv -n $OPERATOR_NAMESPACE"
  echo ""
  echo "   If images failed to pull, verify your pull secret includes"
  echo "   registry.redhat.io credentials:"
  echo "     python3 -c \"import json; ps=json.load(open('$HOME/.crc/pull-secret')); print('registry.redhat.io' in ps.get('auths',{}))\""
  exit 1
fi
echo ""

# ── Step 5: Wait for DSCInitialization ──
echo "── Step 5: Waiting for DSCInitialization ──"
elapsed=0
dsci_ready=false
while (( elapsed < OPERATOR_POLL_TIMEOUT )); do
  dsci_phase="$(oc get dscinitializations.dscinitialization.opendatahub.io default-dsci \
    -o jsonpath='{.status.phase}' 2>/dev/null || true)"

  if [[ "$dsci_phase" == "Ready" ]]; then
    echo "  ✅ DSCInitialization is Ready."
    dsci_ready=true
    break
  elif [[ -n "$dsci_phase" ]]; then
    echo "  ⏳ DSCInitialization phase: $dsci_phase (${elapsed}s / ${OPERATOR_POLL_TIMEOUT}s)"
  else
    echo "  ⏳ DSCInitialization not yet created by operator... (${elapsed}s / ${OPERATOR_POLL_TIMEOUT}s)"
  fi

  sleep "$OPERATOR_POLL_INTERVAL"
  elapsed=$(( elapsed + OPERATOR_POLL_INTERVAL ))
done

if [[ "$dsci_ready" != "true" ]]; then
  echo "⚠️  DSCInitialization did not reach Ready within ${OPERATOR_POLL_TIMEOUT}s."
  echo "   Attempting to apply DSCI template as override..."
  oc apply -f "${CONFIG_DIR}/dsci.yaml"
  sleep 30
fi
echo ""

# ── Step 6: DataScienceCluster ──
echo "── Step 6: Applying DataScienceCluster (all components Managed) ──"
if oc get datascienceclusters.datasciencecluster.opendatahub.io default-dsc &>/dev/null 2>&1; then
  echo "  ⚠️  DataScienceCluster already exists. Updating..."
fi
oc apply -f "${CONFIG_DIR}/dsc.yaml"
echo "  ✅ DataScienceCluster applied."
echo ""

# ── Step 6b: Scale dashboard to 1 replica for single-node CRC ──
# The RHOAI dashboard deployment defaults to 2 replicas for HA. On a
# single-node CRC cluster the second replica stays Pending (insufficient
# CPU/memory), which blocks the DSC from reaching Ready. One replica is
# fully functional — HA is not meaningful on a laptop.
echo "── Step 6b: Scaling dashboard to 1 replica (single-node CRC) ──"
retries=0
while (( retries < 12 )); do
  if oc get deployment rhods-dashboard -n "$APPLICATIONS_NAMESPACE" &>/dev/null 2>&1; then
    oc scale deployment rhods-dashboard -n "$APPLICATIONS_NAMESPACE" --replicas=1 2>/dev/null
    echo "  ✅ Dashboard scaled to 1 replica."
    break
  fi
  retries=$(( retries + 1 ))
  sleep 10
done
if (( retries >= 12 )); then
  echo "  ⚠️  Dashboard deployment not found yet. Scale manually if DSC stays Not Ready:"
  echo "     oc scale deployment rhods-dashboard -n $APPLICATIONS_NAMESPACE --replicas=1"
fi
echo ""

# ── Step 7: Wait for DSC reconciliation ──
echo "── Step 7: Waiting for DataScienceCluster reconciliation ──"
elapsed=0
dsc_ready=false
while (( elapsed < DSC_POLL_TIMEOUT )); do
  dsc_phase="$(oc get datascienceclusters.datasciencecluster.opendatahub.io default-dsc \
    -o jsonpath='{.status.phase}' 2>/dev/null || true)"

  if [[ "$dsc_phase" == "Ready" ]]; then
    echo "  ✅ DataScienceCluster is Ready."
    dsc_ready=true
    break
  elif [[ -n "$dsc_phase" ]]; then
    echo "  ⏳ DataScienceCluster phase: $dsc_phase (${elapsed}s / ${DSC_POLL_TIMEOUT}s)"
  else
    echo "  ⏳ DataScienceCluster status pending... (${elapsed}s / ${DSC_POLL_TIMEOUT}s)"
  fi

  sleep "$OPERATOR_POLL_INTERVAL"
  elapsed=$(( elapsed + OPERATOR_POLL_INTERVAL ))
done

if [[ "$dsc_ready" != "true" ]]; then
  echo "⚠️  DataScienceCluster did not reach Ready within ${DSC_POLL_TIMEOUT}s."
  echo "   Some components may still be reconciling. Run smoke.sh to check."
fi
echo ""

# ── Step 8: Dashboard config ──
echo "── Step 8: Applying dashboard configuration ──"
oc apply -f "${CONFIG_DIR}/dashboard-config.yaml" 2>/dev/null || \
  echo "  ⚠️  Dashboard config apply failed (dashboard may not be ready yet)."
echo ""

# ── Summary ──
echo "── Deployment Summary ──"
echo ""
echo "   Operator CSV:       $(oc get subscription "$OPERATOR_SUBSCRIPTION_NAME" -n "$OPERATOR_NAMESPACE" -o jsonpath='{.status.installedCSV}' 2>/dev/null || echo 'unknown')"
echo "   DSCInitialization:  $(oc get dscinitializations.dscinitialization.opendatahub.io default-dsci -o jsonpath='{.status.phase}' 2>/dev/null || echo 'unknown')"
echo "   DataScienceCluster: $(oc get datascienceclusters.datasciencecluster.opendatahub.io default-dsc -o jsonpath='{.status.phase}' 2>/dev/null || echo 'unknown')"
echo ""

# RHOAI 3.3+ uses a gateway route instead of a direct dashboard route.
dashboard_route="$(oc get route -A -o jsonpath='{range .items[*]}{.spec.host}{"\n"}{end}' 2>/dev/null \
  | grep -m1 'data-science-gateway' || true)"
if [[ -z "$dashboard_route" ]]; then
  dashboard_route="$(oc get route -n "$APPLICATIONS_NAMESPACE" -o jsonpath='{.items[0].spec.host}' 2>/dev/null || true)"
fi
if [[ -n "$dashboard_route" ]]; then
  echo "   🖥️  Dashboard: https://${dashboard_route}"
else
  echo "   🖥️  Dashboard route not yet available. Run smoke.sh after a few minutes."
fi

echo ""
echo "✅ Deployment complete. The work is mysterious and important."
echo "   Run 'bash scripts/smoke.sh' to validate the deployment."
