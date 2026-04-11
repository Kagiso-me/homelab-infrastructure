# ADR-009 — PR-Based Validation Pipeline

**Date:** 2026-03-28
**Last Updated:** 2026-04-05
**Status:** Accepted
**Author:** Kagiso Tjeane

---

## Context

The previous CI/CD model (documented in ADR-005) used a two-environment
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
k3s upgrades, Flux bootstrapping, and secret synchronisation had to be done in both
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

---

## Pipeline Overview

The full pipeline looks like this from the perspective of a single change:

```
Developer opens PR
        │
        ▼
┌─────────────────────────────────────────────────────────┐
│  Job: validate  (GitHub-hosted, ubuntu-latest)          │
│  1. Schema validation — kubeconform                     │
│  2. Overlay correctness — kustomize build               │
│  3. Deprecated API detection — pluto                    │
│  4. Chart version existence — Python + index.yaml fetch │
└────────────────────────┬────────────────────────────────┘
                         │ on success
                         ▼
┌─────────────────────────────────────────────────────────┐
│  Job: cluster-diff  (self-hosted runner: varys)         │
│  flux diff kustomization → posted as PR comment         │
└────────────────────────┬────────────────────────────────┘
                         │ both jobs pass
                         ▼
┌─────────────────────────────────────────────────────────┐
│  Workflow: auto-merge                                   │
│  gh pr merge --squash --delete-branch                   │
└────────────────────────┬────────────────────────────────┘
                         │ merged to main
                         ▼
┌─────────────────────────────────────────────────────────┐
│  Job: health-check  (self-hosted runner: varys)         │
│  1. flux reconcile source git flux-system               │
│  2. kubectl wait kustomization/* --for=condition=ready  │
│  3. Smoke test — Traefik responds at 10.0.10.110        │
└─────────────────────────────────────────────────────────┘
```

All workflow files live in `.github/workflows/`. The jobs in `validate.yml` are
conditionally run — PR jobs on `pull_request` events, health check on `push` to `main`.

---

## Detailed Job Documentation

### Job 1 — `validate` (runs on every PR, GitHub-hosted runner)

**File:** `.github/workflows/validate.yml`, job `validate`
**Runner:** `ubuntu-latest` (GitHub-managed, no homelab dependency)
**Trigger:** Any PR targeting `main` that touches `apps/**`, `platform/**`,
`clusters/**`, or `ansible/**`

This job has no cluster access and no dependency on homelab availability. If `varys`
is powered off, this job still runs. It catches the broadest class of errors — malformed
YAML, broken overlays, deprecated APIs, and non-existent chart versions — all before a
human or the cluster ever sees the change.

#### Step 1 — Schema validation (kubeconform)

**What it does:**
Validates every `.yaml` and `.yml` file in `platform/`, `apps/`, and `clusters/`
(excluding `gotk-components.yaml`, which contains CRD definitions Flux manages) against
the Kubernetes API schema.

**Why we need it:**
Kubernetes silently ignores unknown fields in many contexts. A typo in a field name —
`toleration` instead of `tolerations`, for example — will be accepted by `kubectl apply`
and will silently have no effect. kubeconform catches this in CI before it reaches the
cluster. It also catches structural errors like a missing required field (e.g., forgetting
`spec.selector` on a Deployment).

**Schema sources:**
- Built-in Kubernetes schemas for core resources (Deployments, Services, ConfigMaps, etc.)
- The [datreeio CRDs catalog](https://github.com/datreeio/CRDs-catalog) for Flux CRDs
  (HelmRelease, Kustomization, GitRepository, HelmRepository, etc.) and other custom
  resources from cert-manager, MetalLB, Traefik, Prometheus Operator, and more.

**Flags used:**
- `-strict`: Fails on unknown fields, not just invalid ones. Catches typos.
- `-ignore-missing-schemas`: Skips CRDs that are not in either schema source rather than
  failing. Necessary because the CRD catalog is not exhaustive.

#### Step 2 — Overlay correctness (kustomize build)

**What it does:**
Runs `kustomize build <path>` on every Flux entrypoint in the repository. A Flux entrypoint
is any directory containing a `kustomization.yaml` that Flux directly reconciles (as opposed
to overlays that are only rendered as part of a parent).

**Why we need it:**
`kustomize build` renders the full set of Kubernetes resources that Flux will apply. It
catches errors that schema validation cannot: a `patchesStrategicMerge` patch that
references a non-existent field, a `base` directory that no longer exists, a missing
`namePrefix` that causes duplicate resource names, etc. If `kustomize build` fails, Flux
will also fail to reconcile that path — the CI failure directly predicts the production
failure.

**Entrypoints validated:**
All Flux-managed kustomization paths are listed explicitly in the workflow. This list must
be kept in sync with the Flux `Kustomization` resources in `clusters/prod/`. When adding
a new platform component, add its path to both `infrastructure.yaml` and the workflow list.

#### Step 3 — Deprecated API detection (pluto)

**What it does:**
Pipes the rendered output of each `kustomize build` invocation through `pluto detect`,
which checks for Kubernetes API versions that have been removed or deprecated in the
target cluster version.

**Why we need it:**
Helm chart upgrades and third-party operator updates occasionally change their API versions.
An HelmRelease that renders a resource using `networking.k8s.io/v1beta1/Ingress` will fail
to apply on a cluster running Kubernetes 1.22+, where that version was removed. Pluto
catches this before the chart is deployed. The check uses `|| true` because pluto exits
non-zero when deprecated APIs are detected — we treat this as a warning in CI today, but
it is surfaced in the step output for review.

#### Step 4 — Chart version existence check (Python)

**What it does:**
Scans every `HelmRelease` manifest in the repository, determines which `HelmRepository`
it references, fetches that repository's `index.yaml`, and verifies that the exact chart
version specified in the `HelmRelease` is published and available.

**Why we need it:**
This check was added after a production incident where a `HelmRelease` was updated to
reference a chart version that had not yet been published to the Helm repository. The
HelmRelease went into a failed state immediately, blocking PostgreSQL and Redis from
deploying. This cascaded to Authentik (which requires PostgreSQL) and then to the `apps`
kustomization (which depends on Authentik), taking down the identity provider for the
cluster.

The root cause was a workflow ordering mistake: the version reference in
`homelab-infrastructure` was bumped before the chart was packaged and released in the
`charts` repository.

**The correct workflow is:**
1. Make the change in `/home/kagiso/charts/charts/<name>/`
2. Bump `version:` in the chart's `Chart.yaml`
3. Push to `main` in the `charts` repo
4. Wait for the `Release Charts` GitHub Actions workflow to complete (it packages the chart,
   creates a GitHub Release, and updates the `gh-pages` `index.yaml`)
5. Only then update the `version:` in the `HelmRelease` in `homelab-infrastructure`

If this step is skipped or reversed, the CI check will catch it and block the PR with a
message like:

```
✗ platform/databases/postgresql/helmrelease.yaml:
  postgresql@0.3.3 not found in 'kagiso-me'.
  Available: 0.3.2, 0.3.1, 0.3.0, 0.1.0
  Publish the chart before bumping the version reference.
```

**How it works technically:**
The step runs an inline Python 3 script (no additional installs required — Python 3 and
PyYAML are pre-installed on `ubuntu-latest`). The script:

1. Walks all `*.yaml` files and builds a `name → URL` map from every `HelmRepository` manifest
2. Walks all `*.yaml` files and finds every `HelmRelease` manifest
3. For each HelmRelease, extracts `spec.chart.spec.chart`, `spec.chart.spec.version`, and
   `spec.chart.spec.sourceRef.name`
4. Fetches `{repo_url}/index.yaml` once per unique repository (cached in memory)
5. Checks whether the chart name and version appear in `entries` of the index
6. Exits non-zero if any version is missing, printing all mismatches before failing

---

### Job 2 — `cluster-diff` (runs on every PR, self-hosted runner)

**File:** `.github/workflows/validate.yml`, job `cluster-diff`
**Runner:** `[self-hosted, linux, homelab]` — must be `varys` (10.0.10.10)
**Trigger:** Same as `validate`, runs after `validate` passes (`needs: validate`)

This job requires direct LAN access to the production cluster API server at
`10.0.10.100:6443`. It cannot run on GitHub-hosted runners because GitHub's networks
cannot reach private LAN addresses. The self-hosted runner on `varys` runs inside the
homelab LAN and can reach the cluster directly.

**Runner label requirement:**
The runner must be registered with the labels `self-hosted`, `linux`, and `homelab`.
Without the `homelab` label, GitHub will not assign this job to the runner and it will
queue indefinitely. To verify labels are configured correctly:

```bash
cat /home/kagiso/actions-runner/.runner  # check agentName and registration
sudo systemctl status actions.runner.*    # check service is running
```

To re-register with correct labels (required if the runner was set up without `homelab`):

```bash
cd /home/kagiso/actions-runner
sudo systemctl stop actions.runner.*
sudo ./svc.sh uninstall
./config.sh remove --token <TOKEN>
./config.sh --unattended \
  --url https://github.com/Kagiso-me/homelab-infrastructure \
  --token <TOKEN> \
  --name varys \
  --labels self-hosted,linux,homelab
sudo ./svc.sh install
sudo ./svc.sh start
```

Registration tokens expire after 1 hour. Get a fresh one from:
**Repo → Settings → Actions → Runners → New self-hosted runner**

**What it does:**
Runs `flux diff kustomization <name>` for every Flux-managed kustomization, comparing the
manifests in the PR branch against the live state of the production cluster. The output is
collected into a Markdown comment posted to the PR using `gh pr comment`.

**Why we need it:**
Static validation confirms the manifests are valid Kubernetes. The cluster diff confirms
what will actually change in the cluster. These are different questions. A valid manifest
that happens to delete a running PersistentVolumeClaim is a schema-valid change that static
analysis will not catch. The diff surfaces it as a red line before any human merges.

The comment uses `<details>` blocks so diffs for unchanged kustomizations are collapsed by
default. Only kustomizations with actual changes are expanded.

**Known limitation — "invalid resource path" error:**
`flux diff kustomization` occasionally returns `✗ invalid resource path ""` for
kustomizations that are fully reconciled and up to date. This is a quirk of the `flux diff`
CLI when the kustomization has no local path differences to compute. It does not indicate a
real problem. Check `flux get kustomizations -n flux-system` to verify the actual health of
the kustomization — if it shows `Ready: True`, the "invalid resource path" error can be
ignored.

**Kubeconfig secret:**
The job authenticates to the cluster using the `KUBECONFIG` repository secret, which contains
the raw (not base64-encoded) kubeconfig for the production cluster. The server address is
`10.0.10.100:6443`. This secret must be set in **Repo → Settings → Secrets → Actions**.

---

### Workflow: `auto-merge` (runs after `validate`, GitHub-hosted runner)

**File:** `.github/workflows/auto-merge.yml`
**Runner:** `ubuntu-latest`
**Trigger:** `workflow_run` event — fires when the `Validate & Health Check` workflow
completes. Only acts when the triggering workflow concluded with `success` and was itself
triggered by a `pull_request` event.

**What it does:**
Finds the open PR whose head commit matches the workflow run that just passed, then calls
`gh pr merge --squash --delete-branch`. This merges the PR and deletes the source branch
automatically, with no human interaction required.

**Why we need it:**
This is a solo-operator homelab. Every PR is opened by the same person who will review it.
Requiring a manual merge after CI passes is pure friction — the interesting review happens
at the diff comment stage (cluster-diff), not at a GitHub "Merge" button click. Auto-merge
after CI passes keeps the workflow fast.

**Why `--squash` and not `--merge` or `--rebase`:**
Squash merges keep `git log main` clean. A feature branch with 10 "wip" commits produces
one clean commit on `main` that summarises the change. This matters because `git log main`
is the authoritative deployment history for the cluster.

**How the PR is found:**
The workflow uses `gh pr list --json number,headRefName` filtered to open PRs on non-`main`
branches. Because this is a solo-operator repository with at most one open PR at a time,
the first result is always the correct PR. If multiple PRs are ever open simultaneously,
this logic should be extended to filter by `head_sha` using
`github.event.workflow_run.head_sha`.

**Important — `--auto` flag is not used:**
GitHub's built-in auto-merge feature (`gh pr merge --auto`) requires branch protection rules
with required status checks to be configured. Without branch protection, `--auto` silently
does nothing. This workflow uses a direct merge call instead, which merges immediately when
invoked.

---

### Job 3 — `health-check` (runs after merge to `main`, self-hosted runner)

**File:** `.github/workflows/validate.yml`, job `health-check`
**Runner:** `[self-hosted, linux, homelab]` — must be `varys`
**Trigger:** `push` to `main` for paths in `apps/**`, `platform/**`, `clusters/**`, `ansible/**`

**What it does:**

1. **Force Flux reconciliation** — runs `flux reconcile source git flux-system`, which tells
   Flux to pull the latest commit from GitHub immediately rather than waiting for the next
   poll interval (default: 1 hour). This ensures the health check measures the state after
   the new commit is applied, not the state from before.

2. **Wait for all kustomizations to be Ready** — runs `kubectl wait kustomization/<name>
   --for=condition=ready --timeout=10m` for every Flux-managed kustomization. If any
   kustomization fails to reconcile within 10 minutes (because a HelmRelease failed, a
   resource is invalid on the live cluster, or a dependency is broken), the step fails.

3. **Check for unhealthy pods** — scans all relevant namespaces for pods that are not in
   `Running`, `Completed`, or `Succeeded` state. Prints unhealthy pods and exits non-zero
   if any are found.

4. **Smoke test Traefik** — sends an HTTP request to the MetalLB VIP at `10.0.10.110`.
   Any non-zero HTTP response code (200, 302, 404) indicates Traefik is alive and routing
   traffic. A response of `000` (curl connection refused or timeout) fails the check.

5. **Write step summary** — appends a summary to the GitHub Actions job summary page
   showing the commit SHA, Flux reconciliation status, and Traefik response.

**Why this does not gate the merge:**
The health check runs *after* the PR is already merged. This is intentional. The merge gate
is the `validate` + `cluster-diff` jobs, which run on GitHub-hosted runners with no homelab
dependency. If `varys` is offline, PRs can still merge — the manifests have been statically
validated and the diff has been reviewed. The health check is a fast-feedback signal, not
a blocker. The failure mode is a red GitHub Actions status notification rather than a stuck
merge queue.

---

## HelmRepository Interval

All `HelmRepository` objects should use a short poll interval. The default in Flux is 1h;
the databases repo was previously set to `24h`, which caused a 24-hour delay between
publishing a new chart version and Flux being able to use it. The recommended interval for
any HelmRepository used by active workloads is `5m`.

To force an immediate refresh without waiting for the interval:

```bash
flux reconcile source helm <repo-name> -n flux-system
```

---

## Branch Model

Flux's `GitRepository` source for the production cluster points to:

```yaml
ref:
  branch: main
```

There is no `prod` branch. Every commit that lands on `main` — whether through a regular
PR merge, a revert, or a direct push — is immediately visible to Flux. The reconciliation
interval determines how quickly it is applied (default: 1 hour poll, or immediately on
forced reconciliation via `flux reconcile source git flux-system`).

`git log main` is the authoritative record of what has been deployed to production.

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

**Gate merge on the post-merge health check (require it as a status check)**
This would mean the self-hosted runner on `varys` is in the critical path for all merges.
If `varys` is offline, no PRs can merge. The current model decouples the merge gate (static
analysis on GitHub-hosted runners, always available) from the post-merge health signal
(self-hosted runner, best-effort).

**Tailscale to give GitHub-hosted runners cluster access**
Evaluated and rejected in ADR-005. Creates a hard dependency on a third-party SaaS product
in the merge critical path.

**GitHub's built-in auto-merge with branch protection**
Requires configuring branch protection rules with required status checks. For a solo-operator
homelab this adds administrative overhead with little benefit. The auto-merge workflow
achieves the same result without branch protection.

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

**Chart version existence is enforced at PR time.**
The chart version check prevents the class of incident where a HelmRelease is bumped to a
version that has not yet been published to the Helm repository. This previously caused a
cascading failure: PostgreSQL → Authentik → apps.

**Human review of the exact cluster diff before merge.**
The flux diff comment shows exactly which Kubernetes resources will change. This is a
stronger gate than "staging passed" — it shows the actual impact, not a proxy signal.

**No second cluster to maintain.**
One cluster to upgrade, one set of secrets to rotate, one Flux bootstrap to manage.

**Clean Git history.**
No automated merge commits from a promotion workflow. `git log main` shows only intentional
commits, each representing one unit of change to the cluster.

**Zero-touch merges.**
For routine changes (chart upgrades, config tweaks, new app deployments), the workflow is:
open PR → CI validates → auto-merge → done. No manual clicks after the PR is opened.

### Negative

**Runtime failures are not caught pre-deploy.**
A misconfigured environment variable, a wrong image tag, a chart that requires a pre-existing
database schema, or an application that crashes on startup — none of these are caught by
static analysis. They will only be discovered after the merge lands in production.

This is mitigated by:
- **Kubernetes rolling updates:** The previous `ReplicaSet` stays running until the new
  one is healthy. A crashing pod does not cause a complete outage.
- **HelmRelease remediation:** All HelmReleases are configured with
  `upgrade.remediation.strategy: rollback` — on a failed upgrade, Flux automatically rolls
  back to the previous Helm release revision.
- **Flux health checks and alerting:** Flux marks a HelmRelease `Not Ready` when a rollout
  fails. The monitoring stack and Discord alerting catch this within minutes.
- **Velero backups:** PVC data is backed up daily.
- **Fast revert:** `git revert HEAD && git push origin main` followed by
  `flux reconcile kustomization apps --with-source` undoes a bad deployment in under 2 minutes.

**Post-merge health check is best-effort.**
If `varys` is offline when a PR is merged, the health check does not run. The failure mode
is a missing status check rather than a failing one. Operational dashboards in Grafana
cover the gap.

**Self-hosted runner is a single point of failure for `cluster-diff`.**
If `varys` is down, the `cluster-diff` job will queue indefinitely and the PR cannot merge
(since `cluster-diff` is a required job for auto-merge to trigger). This is intentional —
the cluster diff is a safety gate, not optional — but it means homelab availability affects
CI. Mitigation: ensure the `actions-runner` systemd service is enabled to start on boot
(`sudo systemctl enable actions.runner.*`).

---

## Implementation Notes

### Required GitHub Repository Secrets

| Secret | Value | Where used |
|--------|-------|------------|
| `KUBECONFIG` | Raw kubeconfig (not base64) for `10.0.10.100:6443` | `cluster-diff`, `health-check` |

### Required Repository Settings

- **Actions → General → Workflow permissions:** Read and write (required for `gh pr comment`
  and `gh pr merge`)

### Workflow Files

| File | Jobs | Trigger |
|------|------|---------|
| `.github/workflows/validate.yml` | `validate`, `cluster-diff`, `health-check` | `pull_request` to `main` (validate, cluster-diff); `push` to `main` (health-check) |
| `.github/workflows/auto-merge.yml` | `auto-merge` | `workflow_run` on `Validate & Health Check` completed |

---

## Related

- ADR-005 — Self-Hosted Runners (runner label requirement: `self-hosted`, `linux`, `homelab`)
- `docs/guides/04-Flux-GitOps.md` — Self-hosted runner setup instructions
- `.github/workflows/validate.yml` — Validation + cluster-diff + health-check workflow
- `.github/workflows/auto-merge.yml` — Auto-merge workflow
