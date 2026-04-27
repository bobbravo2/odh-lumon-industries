#!/usr/bin/env bash
set -euo pipefail

# CRC lifecycle helpers for lumon-industries.
# Wraps crc setup/start/stop/delete with ODH-tuned resource allocation
# and readiness polling.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

PULL_SECRET_PATH="${PULL_SECRET_PATH:-$HOME/.crc/pull-secret}"
CRC_MEMORY="${CRC_MEMORY:-28672}"   # 28 GB — tested minimum for all RHOAI components
CRC_CPUS="${CRC_CPUS:-10}"
CRC_DISK="${CRC_DISK:-50}"          # GB

POLL_INTERVAL=15
POLL_TIMEOUT=600  # 10 minutes for cluster readiness

usage() {
  echo "Usage: $(basename "$0") <command>"
  echo ""
  echo "Commands:"
  echo "  setup    Run crc setup (one-time host preparation)"
  echo "  start    Start the CRC cluster with ODH-tuned resources"
  echo "  stop     Stop the CRC cluster gracefully"
  echo "  delete   Delete the CRC cluster entirely"
  echo "  status   Show CRC cluster status"
  echo "  login    Log in to the running cluster as kubeadmin"
  echo ""
  echo "Environment:"
  echo "  PULL_SECRET_PATH  Path to pull secret (default: ~/.crc/pull-secret)"
  echo "  CRC_MEMORY        Memory in MB (default: 18432)"
  echo "  CRC_CPUS          CPU count (default: 6)"
  echo "  CRC_DISK          Disk size in GB (default: 50)"
}

wait_for_cluster() {
  echo "⏳ Waiting for the Severed Floor to come online..."
  local elapsed=0
  while (( elapsed < POLL_TIMEOUT )); do
    if oc whoami &>/dev/null 2>&1; then
      echo "✅ Cluster is responsive. oc whoami: $(oc whoami)"
      return 0
    fi
    sleep "$POLL_INTERVAL"
    elapsed=$(( elapsed + POLL_INTERVAL ))
    echo "   ... still waiting (${elapsed}s / ${POLL_TIMEOUT}s)"
  done
  echo "❌ Cluster did not become responsive within ${POLL_TIMEOUT}s."
  return 1
}

cmd_setup() {
  echo "🏢 Lumon Industries — Preparing the Severed Floor"
  echo ""

  if ! command -v crc &>/dev/null; then
    echo "❌ crc CLI not found. Download from: https://console.redhat.com/openshift/create/local"
    exit 1
  fi

  echo "🔧 Running crc setup..."
  crc setup
  echo ""

  echo "⚙️  Configuring CRC resources for ODH workloads:"
  echo "   Memory: ${CRC_MEMORY} MB"
  echo "   CPUs:   ${CRC_CPUS}"
  echo "   Disk:   ${CRC_DISK} GB"
  crc config set memory "$CRC_MEMORY"
  crc config set cpus "$CRC_CPUS"
  crc config set disk-size "$CRC_DISK"

  echo ""
  echo "✅ Setup complete. Run '$(basename "$0") start' to bring the cluster online."
}

cmd_start() {
  echo "🏢 Lumon Industries — Starting the Severed Floor"
  echo ""

  if ! command -v crc &>/dev/null; then
    echo "❌ crc CLI not found."
    exit 1
  fi

  local ps_args=()
  if [[ -f "$PULL_SECRET_PATH" ]]; then
    ps_args=(--pull-secret-file "$PULL_SECRET_PATH")
    echo "🔑 Using pull secret: $PULL_SECRET_PATH"
  else
    echo "⚠️  No pull secret at $PULL_SECRET_PATH. CRC may prompt for one."
  fi

  echo "🚀 Starting CRC cluster..."
  crc start "${ps_args[@]}"
  echo ""

  echo "🔐 Configuring oc credentials..."
  eval "$(crc oc-env)"

  wait_for_cluster

  echo ""
  echo "✅ The Severed Floor is operational."
  echo "   Console: $(crc console --url 2>/dev/null || echo 'run: crc console --url')"
  echo "   Credentials: kubeadmin / $(crc console --credentials 2>/dev/null | sed -n 's/.*password is \([^ ]*\).*/\1/p' | head -1 || echo 'run: crc console --credentials')"
}

cmd_stop() {
  echo "🏢 Lumon Industries — Stopping the Severed Floor"
  crc stop
  echo "✅ Cluster stopped. Your outie can rest."
}

cmd_delete() {
  echo "🏢 Lumon Industries — Deleting the Severed Floor"
  echo "⚠️  This will destroy the cluster and all data."
  read -rp "   Type 'COMPLIANCE' to confirm: " confirm
  if [[ "$confirm" == "COMPLIANCE" ]]; then
    crc delete --force
    echo "✅ Cluster deleted. The Board has been notified."
  else
    echo "   Deletion cancelled. The Severed Floor remains."
  fi
}

cmd_status() {
  echo "🏢 Lumon Industries — Severed Floor Status"
  echo ""
  crc status
}

cmd_login() {
  echo "🔐 Logging in to the Severed Floor as kubeadmin..."
  eval "$(crc oc-env)"

  if oc config get-contexts "$CRC_CONTEXT" &>/dev/null; then
    oc config use-context "$CRC_CONTEXT" >/dev/null
    if oc whoami &>/dev/null; then
      echo "✅ Switched to CRC context '$CRC_CONTEXT'. Logged in as $(oc whoami)."
      return
    fi
  fi

  local password
  password="$(crc console --credentials 2>/dev/null | sed -n 's/.*password is \([^ ]*\).*/\1/p' | head -1)"
  if [[ -z "$password" ]]; then
    echo "❌ Could not extract kubeadmin password. Is the cluster running?"
    exit 1
  fi
  oc login -u kubeadmin -p "$password" "$CRC_API_SERVER" --insecure-skip-tls-verify
  echo "✅ Logged in as kubeadmin."
}

if (( $# < 1 )); then
  usage
  exit 1
fi

case "$1" in
  setup)  cmd_setup ;;
  start)  cmd_start ;;
  stop)   cmd_stop ;;
  delete) cmd_delete ;;
  status) cmd_status ;;
  login)  cmd_login ;;
  *)
    echo "Unknown command: $1"
    usage
    exit 1
    ;;
esac
