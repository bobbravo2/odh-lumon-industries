# Contributing to lumon-industries

> *"Every department has a purpose. Yours is to make this deployment work."*

Welcome to the Outie Handbook. This document covers how to contribute to
lumon-industries — the thin orchestration wrapper that deploys
[OpenDataHub (ODH)](https://opendatahub.io) on a laptop.

## Getting started

1. **Fork** this repository and create a branch from `main`.
2. **Clone** your fork and make your changes.
3. **Run linting** before opening a pull request (PR):
   ```bash
   shellcheck scripts/*.sh
   ```
4. **Run tests** if you have [bats](https://github.com/bats-core/bats-core)
   installed:
   ```bash
   bats test/
   ```
5. **Open a pull request** with a clear title and description.

## Structure

| Directory | Purpose |
|---|---|
| `scripts/` | Shell scripts for preflight, CRC (OpenShift Local) lifecycle, deploy, and smoke |
| `config/` | OLM (Operator Lifecycle Manager) Custom Resource templates: Subscription (install instruction), DSCInitialization (DSCI), DataScienceCluster (DSC), etc. |
| `docs/` | Supplemental documentation — covers only what differs from the canonical Red Hat docs |
| `test/` | Bats tests for script logic |

## Standards

- **`shellcheck`** — all scripts must pass with zero warnings.
- **Idempotency** — re-running any script must be safe.
- **Fail fast** — if a prerequisite is missing, stop with a clear message.
  Do not silently degrade the deployment.
- **Severance flavour** — keep the Lumon theming light and fun in echo
  messages. The code itself should be dead serious.
- **Docs link upstream** — do not duplicate Red Hat documentation. Link to
  it and document only what differs.

## RBAC awareness

Before opening a PR for features that touch RBAC, dashboard config, or
operator resources:

1. Run `bash scripts/role-check.sh` and verify all checks pass.
2. Test the feature as `developer` (not just `kubeadmin`).

New to RBAC on this project? Run `python3 scripts/rbac-quest.py --persona both`
for a guided walkthrough.

Changes to `role-check.sh` or `rbac-quest.py` must be validated against a
freshly deployed CRC cluster before merging.

## Commit messages

Short, imperative mood. Examples:
- `Add preflight check for CRC version`
- `Fix deploy script readiness timeout`

## Reporting issues

Something explode in the elevator?
[Open an issue](https://github.com/bobbravo2/lumon-industries/issues/new)
with your macOS version, CRC version, and what you expected vs. what happened.

---

*Your outie is grateful for your service.*
