# Roles and Permissions

> *"Not everyone on the Severed Floor has the same clearance."*

This document defines which cluster identity engineers should use for
day-to-day development and testing, and when elevated privileges are
appropriate.

For canonical RBAC documentation, see:
[Red Hat OpenShift AI Self-Managed](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/)

## Default: use `developer/developer`

CRC provides two pre-configured accounts:

| Account | Username | Password | Role |
|---|---|---|---|
| Developer | `developer` | `developer` | Regular authenticated user, no cluster-admin |
| Admin | `kubeadmin` | *(generated, see `crc console --credentials`)* | Full cluster-admin |

**Feature developers should default to `developer/developer` for all
day-to-day work.** This includes:

- Running the dashboard UI
- Creating and using Data Science Projects
- Launching workbenches / notebooks
- Submitting pipelines
- Deploying and querying models
- Any workflow a customer would perform

```bash
oc login -u developer -p developer https://api.crc.testing:6443
```

## Why not kubeadmin?

Using `kubeadmin` (cluster-admin) by default causes real problems:

- **Hidden permission bugs**: code that works under cluster-admin may fail
  for real users who only have namespace-scoped RBAC. If you develop and
  test as kubeadmin, you won't discover these failures until a customer does.
- **Overprivileged defaults**: features that accidentally require
  cluster-admin but shouldn't will ship to production undetected.
- **False confidence in RBAC**: the dashboard and API surfaces behave
  differently for admin vs. non-admin users (different nav items, different
  API responses, different feature flags). Testing only as kubeadmin means
  you've only tested one of the two code paths.

## When to use kubeadmin

Use `kubeadmin` only for operations that genuinely require cluster-level
privileges:

- Installing or upgrading the RHOAI operator
- Modifying `DSCInitialization` or `DataScienceCluster` resources
- Creating or modifying cluster-scoped resources (ClusterRoles, CRDs, etc.)
- Debugging operator reconciliation or cluster-level issues
- Running `deploy.sh` or `smoke.sh` (these require cluster-admin by design)

```bash
oc login -u kubeadmin -p "$(crc console --credentials 2>/dev/null \
  | sed -n 's/.*password is \([^ ]*\).*/\1/p' | head -1)" \
  https://api.crc.testing:6443
```

Or use the lifecycle helper:
```bash
bash scripts/crc-lifecycle.sh login
```

## Multi-role testing

Testing the dashboard and feature access across roles is critical but is
not yet automated in this repo. The minimum manual workflow:

1. **Test as `developer`** — verify the feature works for a regular user.
   This is the default and should be the first and most common test pass.

2. **Test as `kubeadmin`** — verify admin-only features appear and
   function correctly, and that admin operations do not break non-admin
   access.

3. **Compare** — confirm that non-admin users do not see admin-only
   controls, and that admin users see everything they should.

A future follow-up should automate multi-role test runs, potentially using
Cypress or Playwright with separate login sessions per role.

## Adding custom users and groups

For more realistic RBAC testing beyond the two built-in accounts, you can
create additional users and assign them to the RHOAI groups:

```bash
# Create a user with htpasswd identity provider
# (CRC uses htpasswd by default)
oc login -u kubeadmin -p <password> https://api.crc.testing:6443

# Add a user to the RHOAI admin group
oc adm groups new rhods-admins
oc adm groups add-users rhods-admins <username>

# Add a user to the allowed-users group (default: system:authenticated)
# No action needed — all authenticated users can access the dashboard
```

## Summary

| Scenario | Account | Why |
|---|---|---|
| Feature development | `developer` | Matches real customer permissions |
| Dashboard UI testing | `developer` | Tests the non-admin code path |
| Operator or DSC changes | `kubeadmin` | Requires cluster-admin |
| deploy.sh / smoke.sh | `kubeadmin` | Scripts need cluster-level access |
| Multi-role validation | Both | Compare behavior across roles |
