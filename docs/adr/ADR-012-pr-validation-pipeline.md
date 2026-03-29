# ADR-012 — PR-Based Validation Pipeline

**Date:** 2026-03-28
**Status:** Accepted
**Author:** Kagiso Tjeane

---

## Context

The previous CI/CD model (documented in ADR-006 and ADR-007) used a two-environment
promotion pipeline:

1. Changes merged to `main`
2. Staging cluster health checked (single-node k3s on Proxmox VM at 10.0.10.31)
3. If staging is healthy, `main` is automatically merged into a `prod` branch
4. Flux on the production cluster watches the `prod` branch

This model had several problems that accumulated over time:

**The staging cluster gave false confidence.**
Only Grafana's IngressRoute was deployed in staging. The platform layer (Traefik,
cert-manager, kube-prometheus-stack, Velero) was partially configured, but application
HelmReleases — Nextcloud, Immich, n8n — were never deployed there. A passing staging health
check said nothing about whether a change to `apps/base/nextcloud/helmrelease.yaml` would
succeed in production. The dependency chain in staging was different enough from production
that staging failures often indicated staging-specific misconfigurations, not real problems
with the change being tested.

**The staging cluster required constant maintenance.**
k3s upgrades, Flux bootstrapping, and secret synchronization had to be done in both
environments. When the staging cluster was broken (not uncommon after a Proxmox VM
snapshot restore or a k3s version mismatch), the entire CI pipeline blocked. Changes that
had nothing to do with staging were held up waiting for a staging cluster nobody had
touched in weeks.

**The `prod` branch model added friction without safety.**
The production cluster watched the `prod` branch, not `main`. This meant the repository
had two long-lived branches to manage, automated merge commits from the promotion workflow
cluttered the history, and `git log` on `main` did not reflect what was actually running
in production.

**Proxmox was decommissioned.**
The Intel NUC running Proxmox (10.0.10.30) has been converted back to a bare Docker host
at 10.0.10.20. The `staging-k3s` VM no longer exists. The staging environment is gone
regardless of pipeline preference.

The fundamental insight is this: **manifest validation against the actual production cluster
provides more signal than a health check on a different cluster running different workloads.**

---

## Decision

Replace the staging-gate promotion pipeline with a **PR-based validation pipeline** that
validates every change against production-equivalent schemas and the live cluster before
merge. The `prod` branch is eliminated. Flux watches `main` directly.

### Pipeline Design

The pipeline has two phases: **PR validation** (runs before merge) and **post-merge health
check** (runs after merge).

#### PR Validation Phase

All PR validation jobs run on GitHub-hosted `ubuntu-latest` runners. They require no
cluster access and are independent of homelab availability.

| Job | Tool | What It Checks | Runner |
|-----|------|----------------|--------|
| Schema validation | kubeconform | Every YAML file in `platform/`, `apps/`, `clusters/` is valid Kubernetes. CRD schemas sourced from the datreeio CRDs catalog. | `ubuntu-latest` |
| Overlay correctness | kustomize build | Flux entrypoints under `clusters/`, `platform/`, and `apps/prod/` render without errors | `ubuntu-latest` |
| Deprecated API detection | pluto | No manifest uses a Kubernetes API that has been removed or is deprecated in the target version | `ubuntu-latest` |
| Cluster diff preview | flux-local diff | A full diff of what will change in the cluster is rendered and posted as a PR comment | `ubuntu-latest` |

The flux-local diff comment is the key human review signal. Before any PR is merged, the
reviewer sees exactly which Kubernetes resources will be created, updated, or deleted. This
replaces the "did staging stay healthy?" gate with "does this diff look correct?"

#### Post-Merge Health Check Phase

After a PR is merged to `main`, a post-merge job runs on the self-hosted runner (`varys`,
10.0.10.10) which has direct LAN access to the production cluster API server.

```
1. Force Flux source reconciliation (pulls the new main commit immediately)
2. Wait for all Flux kustomizations to report Ready (10 minute timeout per kustomization)
3. Smoke test: Traefik responds at MetalLB VIP (HTTP 200/302/404 — any non-zero code)
4. If any step fails, the workflow fails and GitHub sends a notification
```

This health check verifies that Flux successfully applied the change and the cluster is
in a healthy state. It does not gate the merge — the merge already happened — but it
provides fast feedback if something went wrong, and the GitHub Actions failure creates
a visible alert that demands attention.

### Branch Model

Flux's `GitRepository` source for the production cluster points to:

```
branch: main
```

There is no `prod` branch. Every commit that lands on `main` — whether through a regular
PR merge or a revert — is immediately visible to Flux. The reconciliation interval determines
how quickly it is applied (default: 1 hour poll, or immediately on forced reconciliation).

This means `git log main` is the authoritative record of what has been deployed to
production.

---

## Why Not Alternatives

**Keep the staging cluster, fix the coverage gap**
Deploying all production applications to staging would require maintaining secrets,
database instances, NFS volumes, and external service integrations in a second environment.
The operational cost exceeds the benefit, especially given that the Proxmox host no longer
exists. The staging cluster would need a new home.

**Use Flux's `spec.test` or post-install tests in HelmRelease**
Helm test hooks run inside the cluster post-deploy. They catch some runtime failures but
do not replace pre-merge schema validation or the human diff review that the PR model
provides. They are complementary, not a substitute.

**Gate on prod health check before allowing merge (require status check)**
This would mean the self-hosted runner on `varys` is in the critical path for all merges.
If `varys` is offline, no PRs can merge. The current model decouples the merge gate (static
analysis on GitHub-hosted runners, always available) from the post-merge health signal
(self-hosted runner, best-effort).

**Tailscale to give GitHub-hosted runners cluster access**
Evaluated and rejected in ADR-007. Creates a hard dependency on a third-party SaaS product
in the merge critical path.

---

## Consequences

### Positive

**100% manifest coverage.**
kubeconform validates every YAML file in the repository on every PR. The old staging model
only exercised the subset of resources that were deployed to staging — which excluded most
application HelmReleases.

**Validation against production schemas.**
The kubeconform CRD catalog and pluto checks use the same Kubernetes API versions as the
production cluster. A deprecated API introduced in a chart upgrade is caught before merge,
not after it breaks the production Flux reconciliation.

**Human review of the exact cluster diff before merge.**
The flux-local diff comment shows reviewers what resources will change. This is a stronger
gate than "staging passed" — it requires a human to verify the intent of the change matches
the observed diff.

**No second cluster to maintain.**
One cluster to upgrade, one set of secrets to rotate, one Flux bootstrap to manage. Staging
cluster k3s upgrades, staging Flux drift, and staging-specific breakage are gone.

**Clean Git history.**
No automated merge commits from a promotion workflow. `git log main` shows only intentional
commits.

### Negative

**Runtime failures are not caught pre-deploy.**
A misconfigured environment variable, a wrong image tag, a chart that requires a pre-existing
database schema, or an application that crashes on startup — none of these are caught by
static analysis. They will only be discovered after the merge lands in production.

This is mitigated by several layers:

- **Kubernetes rolling updates:** The previous `ReplicaSet` stays running until the new
  one is healthy. An application that crashes on startup does not cause a complete outage
  — the old pods continue serving traffic while Flux reports a reconciliation error.
- **Flux health checks and alerting:** Flux marks a HelmRelease `Not Ready` when a rollout
  fails. The monitoring stack and Discord alerting catch this within minutes.
- **HelmRelease remediation:** All HelmReleases are configured with `upgrade.remediation.strategy: rollback`
  — on a failed upgrade, Flux automatically rolls back to the previous Helm release revision.
- **Velero backups:** PVC data is backed up daily. Application state can be restored from
  the last successful backup if a deployment corrupts persistent data.
- **Revert is fast:** `git revert HEAD && git push origin main` followed by
  `flux reconcile kustomization apps --with-source` undoes a bad deployment in under 2 minutes.

**Post-merge health check is best-effort.**
If `varys` is offline when a PR is merged, the health check does not run. The failure
mode is silent rather than noisy — there is no red check mark, only a missing one. This is
acceptable because the merge gate (static analysis) has already validated the manifests.
Operational checks in Grafana cover the gap.

---

## Implementation

### Flux GitRepository Change

Update `clusters/prod/flux-system/gotk-sync.yaml` (or equivalent source configuration):

```yaml
apiVersion: source.toolkit.fluxcd.io/v1
kind: GitRepository
metadata:
  name: flux-system
  namespace: flux-system
spec:
  interval: 1h
  ref:
    branch: main    # was: branch: prod
  url: ssh://git@github.com/Kagiso-me/homelab-infrastructure
```

### Workflow Files

| File | Purpose | Runner |
|------|---------|--------|
| `.github/workflows/validate.yml` (job: `validate`) | kubeconform + kustomize build + pluto on PR | `ubuntu-latest` |
| `.github/workflows/validate.yml` (job: `cluster-diff`) | flux diff posted as PR comment | `[self-hosted, linux, homelab]` |
| `.github/workflows/validate.yml` (job: `health-check`) | Post-merge reconcile wait + Traefik smoke test | `[self-hosted, linux, homelab]` |

---

## Related

- ADR-006 — Proxmox Pivot (superseded — Proxmox and staging cluster decommissioned 2026-03-28)
- ADR-007 — Self-Hosted Runners (updated — staging kubeconfig removed, pluto added to tool list)
- `.github/workflows/validate.yml` — combined validation + cluster-diff + health-check workflow
