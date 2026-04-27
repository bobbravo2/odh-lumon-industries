#!/usr/bin/env bash
set -euo pipefail

# Preflight checks for lumon-industries ODH deployment.
# Validates host capacity, required CLIs, CRC, pull-secret,
# cluster type, and competing VMs before doing anything destructive.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

PULL_SECRET_PATH="${PULL_SECRET_PATH:-$HOME/.crc/pull-secret}"
MIN_RAM_GB=16
WARN_RAM_GB=32
MIN_DISK_GB=50
MIN_CORES=4
MIN_MACOS_MAJOR=13

pass=0
warn=0
fail=0

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
echo "🏢 Lumon Industries — Outie Preflight Verification"
echo "   The Board requires all prerequisites be confirmed before deployment."
echo ""

# ── macOS Version ──
section "Operating System"

if [[ "$(uname)" != "Darwin" ]]; then
  fail "This script requires macOS. Detected: $(uname)"
else
  macos_version="$(sw_vers -productVersion)"
  macos_major="${macos_version%%.*}"
  if (( macos_major < MIN_MACOS_MAJOR )); then
    fail "macOS $MIN_MACOS_MAJOR+ required (found $macos_version). CRC needs Hypervisor.framework."
  else
    pass "macOS $macos_version"
  fi
fi

# ── Hardware ──
section "Hardware"

total_ram_bytes="$(sysctl -n hw.memsize 2>/dev/null || echo 0)"
total_ram_gb=$(( total_ram_bytes / 1073741824 ))
if (( total_ram_gb < MIN_RAM_GB )); then
  fail "RAM: ${total_ram_gb} GB (minimum ${MIN_RAM_GB} GB required)"
elif (( total_ram_gb < WARN_RAM_GB )); then
  warn "RAM: ${total_ram_gb} GB (${WARN_RAM_GB} GB recommended for comfortable ODH operation)"
else
  pass "RAM: ${total_ram_gb} GB"
fi

core_count="$(sysctl -n hw.physicalcpu 2>/dev/null || echo 0)"
if (( core_count < MIN_CORES )); then
  fail "CPU cores: ${core_count} (minimum ${MIN_CORES} required)"
else
  pass "CPU cores: ${core_count}"
fi

free_disk_bytes="$(df -k "$HOME" | awk 'NR==2 {print $4}')"
free_disk_gb=$(( free_disk_bytes / 1048576 ))
if (( free_disk_gb < MIN_DISK_GB )); then
  fail "Free disk: ${free_disk_gb} GB (minimum ${MIN_DISK_GB} GB required)"
else
  pass "Free disk: ${free_disk_gb} GB"
fi

# ── Required CLIs ──
section "Required CLIs"

if command -v oc &>/dev/null; then
  pass "oc ($(oc version --client 2>/dev/null | head -1 || echo 'unknown version'))"
else
  fail "oc CLI not found. Install via: brew install openshift-cli"
fi

if command -v crc &>/dev/null; then
  crc_version="$(crc version 2>/dev/null | head -1 || echo 'unknown')"
  pass "crc ($crc_version)"
else
  fail "crc CLI not found. Download from: https://console.redhat.com/openshift/create/local"
fi

if command -v kubectl &>/dev/null; then
  pass "kubectl"
else
  warn "kubectl not found (CRC bundles oc which covers most use cases)"
fi

# ── Pull Secret ──
section "Pull Secret"

if [[ -f "$PULL_SECRET_PATH" ]]; then
  if python3 -c "import json; json.load(open('$PULL_SECRET_PATH'))" 2>/dev/null; then
    pass "Pull secret found at $PULL_SECRET_PATH (valid JSON)"

    rh_registry="$(python3 -c "
import json
ps = json.load(open('$PULL_SECRET_PATH'))
print('yes' if 'registry.redhat.io' in ps.get('auths', {}) else 'no')
" 2>/dev/null || echo 'error')"
    if [[ "$rh_registry" == "yes" ]]; then
      pass "Pull secret includes registry.redhat.io (required for RHOAI images)"
    else
      fail "Pull secret is MISSING registry.redhat.io credentials."
      echo "         RHOAI operator images are hosted on registry.redhat.io."
      echo "         Download an updated pull secret that includes it from:"
      echo "         https://console.redhat.com/openshift/install/pull-secret"
    fi
  else
    fail "Pull secret at $PULL_SECRET_PATH is not valid JSON"
  fi
else
  alt_paths=("$HOME/pull-secret" "$HOME/pull-secret.json" "$HOME/Downloads/pull-secret.txt")
  found=""
  for p in "${alt_paths[@]}"; do
    if [[ -f "$p" ]]; then
      found="$p"
      break
    fi
  done

  if [[ -n "$found" ]]; then
    warn "Pull secret not at $PULL_SECRET_PATH but found at $found. Set PULL_SECRET_PATH=$found or move it."
  else
    fail "Pull secret not found. Download from: https://console.redhat.com/openshift/install/pull-secret"
    echo "         Then place at: $PULL_SECRET_PATH"
    echo "         Or set PULL_SECRET_PATH to its location."
  fi
fi

# ── Competing VMs ──
section "Host Resource Contention"

if ! warn_competing_vms 2>/dev/null; then
  : # warnings already printed by warn_competing_vms
else
  pass "No competing container VMs detected"
fi

# ── Cluster Validation (if CRC is running) ──
section "Cluster Validation"

if command -v crc &>/dev/null; then
  crc_json="$(crc status -o json 2>/dev/null || true)"

  if [[ -n "$crc_json" ]]; then
    crc_vm_state="$(echo "$crc_json" | python3 -c "import sys,json; print(json.load(sys.stdin).get('crcStatus',''))" 2>/dev/null || true)"
    ocp_status="$(echo "$crc_json" | python3 -c "import sys,json; print(json.load(sys.stdin).get('openshiftStatus',''))" 2>/dev/null || true)"
    ocp_version="$(echo "$crc_json" | python3 -c "import sys,json; print(json.load(sys.stdin).get('openshiftVersion',''))" 2>/dev/null || true)"
    crc_preset="$(echo "$crc_json" | python3 -c "import sys,json; print(json.load(sys.stdin).get('preset',''))" 2>/dev/null || true)"
  else
    crc_vm_state=""
  fi

  if [[ "$crc_vm_state" == "Running" ]]; then
    pass "CRC VM: Running (OpenShift $ocp_version, preset: $crc_preset)"

    if [[ "$ocp_status" == "Running" ]]; then
      pass "OpenShift API: Running"
    else
      warn "OpenShift API: ${ocp_status:-unknown} (may still be starting)"
    fi

    if [[ "$crc_preset" != "openshift" ]]; then
      fail "CRC preset is '$crc_preset', not 'openshift'. ODH requires the openshift preset."
    fi

    # Check kubeconfig context
    if oc config get-contexts "$CRC_CONTEXT" &>/dev/null 2>&1; then
      pass "CRC kubeconfig context '$CRC_CONTEXT' exists"

      current_ctx="$(oc config current-context 2>/dev/null || true)"
      if [[ "$current_ctx" == "$CRC_CONTEXT" ]]; then
        pass "oc is pointed at CRC context"
      else
        warn "oc is pointed at '$current_ctx', not CRC. Deploy will switch to '$CRC_CONTEXT'."
      fi
    else
      warn "CRC kubeconfig context '$CRC_CONTEXT' not found. Run: bash scripts/crc-lifecycle.sh login"
    fi

    # Check OpenShift APIs and OLM via the CRC context
    eval "$(crc oc-env 2>/dev/null)"
    saved_ctx="$(oc config current-context 2>/dev/null || true)"
    oc config use-context "$CRC_CONTEXT" >/dev/null 2>&1 || true

    ocp_apis="$(oc api-resources --api-group=config.openshift.io 2>/dev/null || true)"
    if echo "$ocp_apis" | grep -q clusterversions; then
      pass "OpenShift APIs confirmed on CRC cluster"
    else
      fail "CRC cluster missing OpenShift APIs (cluster may not have started fully)"
    fi

    olm_apis="$(oc api-resources --api-group=operators.coreos.com 2>/dev/null || true)"
    if echo "$olm_apis" | grep -q subscriptions; then
      pass "OLM (Operator Lifecycle Manager) is available"
    else
      fail "OLM is not available on CRC cluster. Try: crc stop && crc start"
    fi

    # Restore original context
    if [[ -n "$saved_ctx" ]]; then
      oc config use-context "$saved_ctx" >/dev/null 2>&1 || true
    fi
  else
    warn "CRC VM is not running (state: ${crc_vm_state:-unknown}). Start it before deploying."
  fi
else
  warn "crc CLI not installed — skipping cluster validation"
fi

# ── Summary ──
echo ""
echo "── Preflight Summary ──"
echo "   Passed: $pass"
echo "   Warnings: $warn"
echo "   Failed: $fail"
echo ""

if (( fail > 0 )); then
  echo "❌ Preflight FAILED. The Board cannot approve this deployment."
  echo "   Resolve the failures above before proceeding."
  exit 1
elif (( warn > 0 )); then
  echo "⚠️  Preflight PASSED with warnings. Deployment may proceed, but your"
  echo "   outie should address the warnings for a stable experience."
  exit 0
else
  echo "✅ Preflight PASSED. The Severed Floor is ready for deployment."
  exit 0
fi
