#!/usr/bin/env bash
# Shared helpers for lumon-industries scripts.
# Source this file; do not execute it directly.

CRC_CONTEXT="crc-admin"
export CRC_API_SERVER="https://api.crc.testing:6443"

# Operator identity — RHOAI downstream ships arm64, community ODH does not.
# Pull secret must include registry.redhat.io credentials.
# Download from: https://console.redhat.com/openshift/install/pull-secret
export OPERATOR_SUBSCRIPTION_NAME="rhods-operator"
export OPERATOR_NAMESPACE="openshift-operators"
export APPLICATIONS_NAMESPACE="redhat-ods-applications"

# Switch oc to the CRC admin context, validating it exists and is reachable.
# Exits with actionable error if CRC context is missing or cluster is down.
use_crc_context() {
  eval "$(crc oc-env 2>/dev/null)"

  if ! oc config get-contexts "$CRC_CONTEXT" &>/dev/null; then
    echo "❌ Kubeconfig context '$CRC_CONTEXT' not found."
    echo "   Your oc is currently pointed at: $(oc config current-context 2>/dev/null || echo 'none')"
    echo ""
    echo "   This usually means CRC has not been started yet, or 'crc start'"
    echo "   did not add its context to your kubeconfig."
    echo ""
    echo "   Fix: bash scripts/crc-lifecycle.sh start"
    exit 1
  fi

  local current
  current="$(oc config current-context 2>/dev/null || true)"
  if [[ "$current" != "$CRC_CONTEXT" ]]; then
    echo "⚠️  Switching kubeconfig context from '$current' to '$CRC_CONTEXT'"
    oc config use-context "$CRC_CONTEXT" >/dev/null
  fi

  if ! oc whoami &>/dev/null; then
    echo "❌ Context '$CRC_CONTEXT' exists but cluster is not responding."
    echo "   Is CRC running? Check: crc status"
    exit 1
  fi
}

# Verify the target cluster is OpenShift (not plain Kubernetes).
require_openshift() {
  local api_out
  api_out="$(oc api-resources --api-group=config.openshift.io 2>/dev/null || true)"
  if ! echo "$api_out" | grep -q clusterversions; then
    echo "❌ The current cluster is not OpenShift."
    echo "   oc is pointed at: $(oc whoami --show-server 2>/dev/null || echo 'unknown')"
    echo "   Context: $(oc config current-context 2>/dev/null || echo 'unknown')"
    echo ""
    echo "   lumon-industries requires an OpenShift cluster (CRC)."
    echo "   You may be pointed at a plain KinD or other Kubernetes cluster."
    echo ""
    echo "   Fix: bash scripts/crc-lifecycle.sh login"
    exit 1
  fi
}

# Verify OLM (Operator Lifecycle Manager) is available on the cluster.
require_olm() {
  local api_out
  api_out="$(oc api-resources --api-group=operators.coreos.com 2>/dev/null || true)"
  if ! echo "$api_out" | grep -q subscriptions; then
    echo "❌ OLM (Operator Lifecycle Manager) is not available on this cluster."
    echo "   The ODH operator is installed via OLM Subscriptions."
    echo ""
    echo "   On a CRC OpenShift cluster, OLM should be pre-installed."
    echo "   If you see this error on CRC, the cluster may not have started"
    echo "   fully. Try: crc stop && crc start"
    exit 1
  fi
}

# Warn if other VMs or container machines are eating host resources.
warn_competing_vms() {
  local warnings=0

  if command -v podman &>/dev/null; then
    local running_machines
    running_machines="$(podman machine list --format '{{.Name}} {{.Running}}' 2>/dev/null | grep -c true || true)"
    if (( running_machines > 0 )); then
      echo "  ⚠️  $running_machines podman machine(s) running alongside CRC."
      echo "     These compete for RAM and CPU. Consider stopping them:"
      echo "     podman machine stop"
      warnings=$(( warnings + 1 ))
    fi
  fi

  if command -v docker &>/dev/null; then
    if docker info &>/dev/null 2>&1; then
      echo "  ⚠️  Docker Desktop is running alongside CRC."
      echo "     This competes for host resources."
      warnings=$(( warnings + 1 ))
    fi
  fi

  return "$warnings"
}
