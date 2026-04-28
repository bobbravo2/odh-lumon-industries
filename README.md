# Lumon Industries

> *"Your outie has generously volunteered you for this deployment."*

**lumon-industries** is a thin orchestration wrapper that deploys the full
[OpenDataHub (ODH)](https://opendatahub.io) /
[Red Hat OpenShift AI (RHOAI)](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/)
product on your laptop using
[OpenShift Local (CRC)](https://developers.redhat.com/products/openshift-local).

It does not invent a new deployment model. It automates the documented
OLM (Operator Lifecycle Manager) install flow. In Kubernetes, an *operator*
is a controller that automates managing a complex application; OLM handles
installing and updating operators. This script applies known-good Custom
Resources (Kubernetes objects that configure the operator) in the correct
order, polls for readiness, and validates the result — so your outie can
stop pretending the cluster is someone else's problem.

Think of it as the **Board's approved procedure** for running the Severed Floor
locally. Your innie provisions the workstation
([innie](https://github.com/bobbravo2/innie)); your outie provisions the
product.

## Prerequisites


| Requirement                                                                     | Minimum                                             | Tested                     |
| ------------------------------------------------------------------------------- | --------------------------------------------------- | -------------------------- |
| macOS                                                                           | 13 (Ventura)                                        | Latest                     |
| RAM                                                                             | 32 GB (28 GB for CRC)                               | 48 GB                      |
| Disk                                                                            | 50 GB free                                          | 100 GB free                |
| CPU                                                                             | 6 physical cores                                    | 10+ cores allocated to CRC |
| [OpenShift Local (CRC)](https://console.redhat.com/openshift/create/local)      | Installed                                           | Latest                     |
| [Red Hat pull secret](https://console.redhat.com/openshift/install/pull-secret) | Present on disk (must include `registry.redhat.io`) | --                         |
| `oc` CLI (OpenShift command-line client)                                        | Installed                                           | --                         |


Optional: run [innie](https://github.com/bobbravo2/innie) first to bootstrap
Homebrew, `oc`, `gh`, and other workstation dependencies.

## Quick start

```bash
git clone https://github.com/bobbravo2/lumon-industries.git && cd lumon-industries && bash run.sh
```

That single command runs preflight checks, starts the CRC cluster, deploys
the full ODH product via OLM, and validates the result. When it finishes,
open the dashboard route (URL) printed at the end. The work is mysterious and
important.

If you prefer to run the stages individually:

```bash
bash scripts/preflight.sh           # verify prerequisites
bash scripts/crc-lifecycle.sh start  # start the cluster
bash scripts/deploy.sh              # deploy ODH
bash scripts/smoke.sh               # validate
bash scripts/role-check.sh          # validate RBAC boundaries
```

## RBAC onboarding

After deployment, validate that role-based access controls are working
and learn how they map to platform engineer / data scientist workflows:

```bash
bash scripts/role-check.sh          # 30-second automated RBAC parity check
bash quest.sh --persona both        # interactive guided walkthrough (~20 min)
```

The quest runner requires Python 3 and the `rich` package:

```bash
pip install -r requirements.txt
```

## What gets deployed

The deploy script applies the documented OLM install flow using the
**RHOAI downstream operator** (`rhods-operator`), which ships multi-arch
images including arm64 for Apple Silicon:

1. Applications namespace (`redhat-ods-applications`)
2. OperatorGroup (determines which namespaces the operator manages)
3. OLM Subscription (`rhods-operator` from the `redhat-operators` catalog, `fast-3.x` channel)
4. `DSCInitialization` (DSCI) — cluster-wide initialization; auto-created by the operator
5. `DataScienceCluster` (DSC) — declares which components to enable; all set to `Managed`

The dashboard is accessible via the gateway route at
`https://data-science-gateway.apps-crc.testing` after deploy completes.

All templates live in `config/` and can be overridden for custom configurations.

## Documentation


| Document                                                                                                 | Description                                        |
| -------------------------------------------------------------------------------------------------------- | -------------------------------------------------- |
| [Host requirements](docs/host-requirements.md)                                                           | Hardware floor and CRC version guidance            |
| [Parity scope](docs/parity-scope.md)                                                                     | What "full product" means on a laptop              |
| [Roles and permissions](docs/roles-and-permissions.md)                                                   | Use `developer`, not `kubeadmin`, for feature work |
| [RBAC quest guide](docs/rbac-quest-guide.md)                                                             | Gamified RBAC onboarding for platform engineers and data scientists |
| [Relationship to innie](docs/relationship-to-innie.md)                                                   | How this repo relates to workstation bootstrap     |
| [Red Hat OpenShift AI docs](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/) | Canonical upstream documentation                   |


## Contributing

Contributions are welcome. See [CONTRIBUTING.md](CONTRIBUTING.md) for the
outie's handbook.

## Disclaimer

*Severance* and all related names, characters, and indicia are trademarks of
Apple Inc. This project is not affiliated with, endorsed by, or sponsored by
Apple Inc. in any way.

## License

[MIT](LICENSE)

---

*The Board thanks you for your cooperation. Please try to enjoy each deployment equally.*