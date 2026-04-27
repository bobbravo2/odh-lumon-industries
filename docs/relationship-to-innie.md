# Relationship to innie

> *"Your innie provisions the workstation. Your outie provisions the product."*

## What is innie?

[innie](https://github.com/bobbravo2/innie) is an idempotent (safe to re-run) macOS setup
script that installs workstation dependencies via Homebrew: `oc` (OpenShift
CLI), `gh` (GitHub CLI), `uv` (Python package manager), Python, Cursor,
Claude, and other developer tools.

## What is lumon-industries?

**lumon-industries** is the outie-side companion that deploys the full
OpenDataHub (ODH) product on a laptop using OpenShift Local (CRC) and the
documented OLM (Operator Lifecycle Manager) install flow.

## How they relate

```
innie (workstation bootstrap)
  └── installs: brew, oc, gh, python, cursor, ...
  └── scope: macOS dependency install, idempotent, no secrets

lumon-industries (product deployment)
  └── orchestrates: CRC, OLM, operator, DSCI (DSCInitialization), DSC (DataScienceCluster)
  └── scope: cluster lifecycle (start, stop, configure), authenticated, stateful
```

## Is innie required?

**No.** `lumon-industries` checks for its own prerequisites independently
via `preflight.sh`. If you already have `oc` and `crc` installed through
any means, you do not need to run `innie` first.

However, if you are setting up a new Mac from scratch, running `innie` first
will install most of the CLI tools that `lumon-industries` depends on.

## Why separate repos?

- **Different trust boundaries**: `innie` never touches secrets or
  authenticated services. `lumon-industries` requires a Red Hat pull secret
  and manages cluster state.
- **Different lifecycles**: workstation bootstrap changes rarely;
  product deployment tracks upstream (open-source project) operator releases.
- **Different failure modes**: a failed `brew install` is annoying;
  a failed operator reconciliation (the operator failing to bring the cluster
  to its desired state) on a single-node cluster needs diagnosis
  and potentially manual intervention.
- **Different audiences**: `innie` is for anyone joining the team.
  `lumon-industries` is for engineers who need the product running locally.
