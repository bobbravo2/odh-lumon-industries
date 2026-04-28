# RBAC Quest Guide

> *"Not every department needs to see every file. That's not a bug — it's a feature."*

This document explains why RBAC matters for this project, maps cluster
personas to Lumon divisions, and describes the tools available for
validating role boundaries.

For canonical RBAC documentation, see:
[Red Hat OpenShift AI Self-Managed](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/)

## Why RBAC is a business gate

> **Disclaimer:** This is a developer education and validation tool, not a
> compliance certification tool. It validates that RBAC boundaries are
> correctly enforced on your local cluster. It does not provide SOC 2,
> ISO 27001, or any other regulatory compliance assurance.

RBAC misconfigurations tend to be invisible until they are expensive.
Three real-world patterns:

### The model that worked in dev (Banking)

A credit-scoring model is developed and tested as `cluster-admin`. It ships
with a missing RoleBinding. Production returns 403 during a regulatory
reporting window. The emergency change approval to fix it is itself a
compliance event — auditable, time-stamped, and cited in the next
examination.

### The shared namespace incident (Telco)

Two teams share a namespace. A training job overwrites a PersistentVolumeClaim.
Three weeks of curated data is lost. Root cause: the platform engineer
tested as admin and never saw the permission boundary that would have
prevented the cross-team write.

### The overprivileged pipeline (Insurance)

A pipeline ServiceAccount is granted `cluster-admin`. A compromised notebook
reads Secrets across all namespaces. The gap is found during a SOC 2 Type II
audit — months after the exposure began.

## Persona model (Lumon divisions)

### MDR — Macrodata Refinement (Data Scientist)

Account: `developer` — namespace-scoped.

**Can do:**
- Create Data Science Projects
- Launch workbenches and notebooks
- Submit and monitor pipelines
- Deploy and query models

**Cannot do:**
- Access cluster infrastructure (nodes, operators, CRDs)
- Modify operator resources (DSCInitialization, DataScienceCluster)
- See other teams' namespaces

### O&D — Optics & Design (Platform Engineer)

Account: `kubeadmin` — cluster-scoped.

**Owns:**
- Operator lifecycle (install, upgrade, removal)
- Group management (`rhods-admins`, allowed groups)
- DSCInitialization and DataScienceCluster configuration
- OdhDashboardConfig and feature flags

### The Board (Cluster Admin — break-glass)

**When it's used:**
- Initial cluster deployment (`deploy.sh`)
- Operator install or major upgrade
- Break-glass recovery

This role should be rare and auditable. If you are using `kubeadmin` for
day-to-day feature work, you are testing the wrong code path.

### How groupsConfig maps

In `config/dashboard-config.yaml`, the `OdhDashboardConfig` defines:

```yaml
groupsConfig:
  adminGroups: rhods-admins
  allowedGroups: "system:authenticated"
```

- `adminGroups: rhods-admins` — members see admin nav items and can manage
  cluster-scoped resources through the dashboard.
- `allowedGroups: system:authenticated` — any authenticated user can access
  the dashboard. Restrict this to lock down access.

> **Limitation:** Namespace RBAC does not provide network isolation.
> NetworkPolicy is a separate concern and is out of scope for this tool.

## Tool reference

### role-check.sh (primary)

Automated RBAC parity matrix. Runs in ~30 seconds.

```bash
bash scripts/role-check.sh
```

**What it checks:**
- MDR persona — `developer` impersonation via `oc auth can-i --as=`
- O&D persona — admin-level access checks
- Cross-persona config — verifies groupsConfig, dashboard feature flags

**Reading the output:** results are grouped by persona with pass/warn/fail
status for each check. All checks should pass before opening a PR that
touches RBAC, dashboard config, or operator resources.

### rbac-quest.py (optional deep-dive)

Interactive gamified RBAC learning with persona tracks.

**Prerequisites:**

```bash
pip install -r requirements.txt
```

**Usage:**

```bash
bash quest.sh --persona mdr|od|both
```

| Flag | Description |
|---|---|
| `--persona mdr\|od\|both` | Choose a persona track |
| `--level N` | Start at a specific level |
| `--dry-run` | Preview checks without running them |
| `--skip-orientation` | Skip the intro sequence |
| `--status` | Show current progress |
| `--cleanup` | Remove quest state files |

**Time estimates:** ~10 min per track, ~20 min for full clearance.

Quest level details are available via `bash quest.sh --help`.

## Integration

### Pre-PR checklist

Before opening a PR that touches RBAC, dashboard config, or operator
resources:

1. Run `bash scripts/role-check.sh` — all checks pass.
2. Test the feature as `developer` (not just `kubeadmin`).
3. If adding a new role-check or quest level, run the full suite.
4. See [CONTRIBUTING.md](../CONTRIBUTING.md) for the complete PR checklist.

### Manual integration testing

Before releasing changes to `role-check.sh` or `rbac-quest.py`, run the
full tool against a freshly deployed CRC cluster. Stale cluster state
can mask permission drift.
