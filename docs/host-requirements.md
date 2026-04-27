# Host Requirements

> *"The Board has reviewed your hardware and found it... adequate."*

This document covers the minimum and recommended specifications for running the
full [Red Hat OpenShift AI (RHOAI)](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/)
product on your laptop via [OpenShift Local (CRC)](https://developers.redhat.com/products/openshift-local).

For the canonical product documentation, see:
[Red Hat OpenShift AI Self-Managed](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/)

## Hardware

| Resource | Minimum | Tested | Notes |
|---|---|---|---|
| RAM | 16 GB | 48 GB (28 GB allocated to CRC) | CRC alone needs 9 GB; all RHOAI components need ~28 GB to schedule |
| CPU | 4 physical cores | 14 cores (10 allocated to CRC) | 6 CPUs was insufficient for all components; 10 is the tested minimum |
| Disk | 50 GB free | 100 GB free | CRC VM image + container images + workbench storage |
| Architecture | x86_64 or Apple Silicon | Apple Silicon (arm64) | See "Why RHOAI, not community ODH" below |

## Why RHOAI, not community ODH

The community [OpenDataHub operator](https://github.com/opendatahub-io/opendatahub-operator)
publishes **amd64-only** container images. On Apple Silicon Macs, CRC runs a
native arm64 VM, and the amd64 operator binary crashes with a Go runtime panic
(`lfstack.push`) under Rosetta emulation.

The downstream **RHOAI operator** (`rhods-operator`) from the `redhat-operators`
catalog ships **multi-arch images** (amd64, arm64, ppc64le, s390x) and runs
natively on Apple Silicon CRC. This is why `lumon-industries` uses `rhods-operator`
instead of `opendatahub-operator`.

## Operating System

- **macOS 13 (Ventura) or later** — required for CRC's use of
  Apple Hypervisor.framework

## Software Prerequisites

| Tool | Required | Install |
|---|---|---|
| [OpenShift Local (CRC)](https://console.redhat.com/openshift/create/local) | Yes | Download from Red Hat console (not Homebrew) |
| [Red Hat pull secret](https://console.redhat.com/openshift/install/pull-secret) | Yes | Download and save to `~/.crc/pull-secret` |
| `oc` CLI (OpenShift command-line client) | Yes | `brew install openshift-cli` or download from CRC |
| `kubectl` (Kubernetes command-line tool) | Optional | CRC bundles `oc` which covers most use cases |

### Why not Homebrew for CRC?

The Homebrew-installed version of CRC does not include the OpenShift bundle
(the pre-built VM image containing the cluster). You would need to manually
specify a bundle path with `-b`, which defeats the purpose. Use the official
installer from the Red Hat console.

## Pull Secret — registry.redhat.io

Your Red Hat pull secret **must include credentials for `registry.redhat.io`**.
RHOAI operator images are hosted there, and without valid credentials the
operator pods will fail to pull images and never start.

The standard pull secret from https://console.redhat.com/openshift/install/pull-secret
includes `registry.redhat.io` by default. CRC injects the pull secret into the
cluster during `crc start`, so no additional auth configuration is needed.

The preflight script validates this:
```bash
bash scripts/preflight.sh
# Look for: ✅ Pull secret includes registry.redhat.io
```

Save the pull secret to `~/.crc/pull-secret` or set `PULL_SECRET_PATH` to
its location. **Never commit pull secrets to version control.**

## CRC Resource Tuning

The `crc-lifecycle.sh` script configures CRC with tested defaults:

| Setting | Default | Override | Notes |
|---|---|---|---|
| Memory | 28672 MB (28 GB) | `CRC_MEMORY=<mb>` | 18 GB was insufficient for all components |
| CPUs | 10 | `CRC_CPUS=<count>` | 6 CPUs caused scheduling failures |
| Disk | 50 GB | `CRC_DISK=<gb>` | |

These defaults were validated on a 48 GB / 14-core Apple Silicon Mac.
On machines with less than 32 GB total RAM, reduce `CRC_MEMORY` and set
resource-heavy components to `Removed` in `config/dsc.yaml`.

## CRC Version and OCP Compatibility

RHOAI 3.x requires OpenShift Container Platform (OCP) 4.19+.
Check your CRC version's bundled OCP version:

```bash
crc version
```

If the bundled OCP version is older than 4.19, update CRC before deploying.

## Multi-Cluster Awareness

If you run other local Kubernetes clusters (KinD, minikube, other CRC
instances), `lumon-industries` explicitly switches to the `crc-admin`
kubeconfig context before any cluster operation. It will not accidentally
deploy to the wrong cluster.

The preflight script warns if your `oc` context is pointed elsewhere,
and the deploy/smoke scripts switch automatically.
