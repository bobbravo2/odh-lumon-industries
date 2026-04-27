# Parity Scope

> *"You will try to enjoy all components equally."*

This document defines what "full product on a laptop" means, what is likely
to work, and what is known to struggle on constrained single-node hardware.

For the canonical component documentation, see:
[Red Hat OpenShift AI Self-Managed](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/)

## What strict parity means

The `config/dsc.yaml` template sets **every** component in the
`DataScienceCluster` (DSC) Custom Resource (the central Kubernetes object
that declares which components are enabled) to `Managed` (active and
operator-controlled). This is intentional: the goal is to attempt a full
product deployment rather than silently reducing the scope.

If a component fails to reconcile (reach its desired running state) on your
hardware, the smoke script will report it. This document records the known
constraints so you can make informed decisions about what to set to
`Removed` (disabled) on your machine.

## RHOAI 3.3+ API Changes

The DSC API changed significantly in RHOAI 3.3. The template uses
`apiVersion: datasciencecluster.opendatahub.io/v2`. Key changes from
earlier versions:

- `datasciencepipelines` was renamed to `aipipelines`
- `modelmeshserving` was removed (replaced by KServe RawDeployment mode)
- `kserve.serving` sub-field was removed (RawDeployment is the only mode)
- New components added: `feastoperator`, `llamastackoperator`, `mlflowoperator`, `trainer`

## Component expectations on a laptop

Tested on a 48 GB / 14-core Apple Silicon Mac with CRC at 28 GB / 10 CPUs.

| Component | Status (Tested) | Notes |
|---|---|---|
| **Dashboard** | Works (1 replica) | See "Dashboard HA replica" below |
| **Workbenches** | Works | Notebook controller pods need ~10 min to schedule on tight clusters |
| **AI Pipelines** (formerly Data Science Pipelines) | Works | Requires MariaDB/Minio; resource-hungry on single node |
| **KServe** | Works (controller only) | RawDeployment mode only; LLM inference dependencies need Serverless subscription |
| **Ray** | Works (controller only) | KubeRay operator starts; actual distributed compute is aspirational on one node |
| **Kueue** | Error | Job queue manager; may need prerequisite Red Hat build of Kueue operator |
| **Training Operator** | Works (controller only) | No GPU on standard laptops |
| **Trainer** | Error | Newer training component; may need JobSet operator prerequisite |
| **TrustyAI** | Works | Lightweight model explainability and bias-detection service |
| **Model Registry** | Works | Lightweight metadata service for tracking model versions |
| **Feast Operator** | Works | Feature store operator |
| **Llama Stack Operator** | Works | LlamaStack deployment operator |
| **MLflow Operator** | Works | Experiment tracking and model lifecycle operator |

## Dashboard HA replica issue

The RHOAI dashboard deployment requests 2 replicas by default. On a
resource-constrained CRC cluster, the second replica often stays `Pending`
because the scheduler cannot find enough CPU/memory headroom. This causes the
DSC to report `DashboardReady: False (DeploymentsNotReady)`.

The fix is to scale the dashboard to 1 replica:
```bash
oc scale deployment rhods-dashboard -n redhat-ods-applications --replicas=1
```

This makes the operator mark the dashboard as Ready. The dashboard is fully
functional with a single replica — the second is purely for high availability,
which is not meaningful on a single-node laptop cluster.

## Dashboard access via gateway route

RHOAI 3.3+ uses a **gateway route** instead of a direct dashboard route.
The dashboard is accessible at:

```
https://data-science-gateway.apps-crc.testing
```

This route is created automatically by the operator via the `openshift-ingress`
namespace. The deploy and smoke scripts look for this gateway route pattern.

Login with the CRC kubeadmin credentials:
```bash
crc console --credentials
```

## Prerequisite operators

Some components depend on external operators that must be installed
separately. These are **not** installed by `deploy.sh`:

| Operator | Needed By | On CRC |
|---|---|---|
| Cert Manager (TLS certificate management) | KServe, Gateway | Available via OperatorHub |
| Red Hat build of Kueue | Kueue component | Available via OperatorHub |
| Jobset Operator (batch job groups) | Trainer component | Available via OperatorHub |
| OpenShift Serverless (Knative) | KServe LLM inference | Heavy; may not fit on constrained nodes |
| Service Mesh (Istio networking) | KServe Serverless mode | Heavy; may not fit on constrained nodes |

## Known laptop-specific issues

- **Image pull times**: first deploy can take 20-30 minutes as CRC pulls
  all operator and component container images from `registry.redhat.io`.
- **CPU scheduling pressure**: with all components Managed at 10 CPUs,
  the node runs at ~97% CPU requests. Additional workloads may not schedule.
- **Pod eviction**: on RAM-constrained machines, Kubernetes may evict
  (forcibly terminate) pods under memory pressure. Monitor with
  `oc get events --sort-by=.lastTimestamp`.
- **No GPU**: model serving and training workflows that require GPU
  acceleration will not work on standard laptop hardware.
- **CRC restarts**: CRC state is preserved across `crc stop` / `crc start`,
  but the operator will re-reconcile on startup, which takes a few minutes.
- **Competing VMs**: running podman machines or Docker Desktop alongside CRC
  competes for host RAM and CPU. The preflight script warns about this.

## Adjusting for your machine

Edit `config/dsc.yaml` before running `deploy.sh` to set specific components
to `Removed`:

```yaml
spec:
  components:
    ray:
      managementState: Removed    # not useful on single-node
    trainer:
      managementState: Removed    # needs JobSet operator
    feastoperator:
      managementState: Removed    # free up resources
```

This is not a failure — it is an honest assessment of what fits. The smoke
script will report the actual state of every component.
