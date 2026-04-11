# ADR-012 — Automated Upgrade Strategy

**Date:** 2026-04-08
**Status:** Accepted
**Author:** Kagiso Tjeane

---

## Context

A homelab cluster running production-grade services requires a disciplined upgrade strategy.
Dependencies — Helm charts, Docker images, GitHub Actions, Flux itself — are constantly
publishing new versions. Without automation, upgrades accumulate until a manual update session
becomes a high-risk batch operation. With too much automation, an untested breaking change can
silently land in the cluster at 2am.

The goals are:

- Dependencies stay reasonably current without manual tracking
- Safe updates (patches, digests) merge and deploy without human involvement
- Risky updates (minor, major, Kubernetes-related) are flagged for human review before merging
- Upgrades happen at predictable, low-impact times — not during business hours

---

## Decision

Use **Renovate Bot** for automated dependency discovery and PR creation, combined with the
**PR validation pipeline** (ADR-009) for safety gating, with selective auto-merge based on
update risk level.

---

## Upgrade Flow

```
Renovate scans repo (after 6pm weekdays / weekends)
        │
        ▼
Opens PR with version bump
        │
        ▼
┌─────────────────────────────────────────────────┐
│  Validate & Health Check CI                     │
│  1. kustomize build — manifest correctness      │
│  2. kubeconform — schema validation             │
│  3. pluto — deprecated API detection            │
│  4. chart version existence check               │
│  5. cluster-diff — what changes in production   │
└───────────────┬─────────────────────────────────┘
                │
        ┌───────┴────────┐
        │                │
   Auto-merge?        Manual review
   (patch/digest)     (minor/major/k8s)
        │
        ▼
  Squash merge → main
        │
        ▼
  Flux reconciles cluster
        │
        ▼
  Post-merge health check
```

---

## Schedule

Renovate runs on the following schedule (Africa/Johannesburg timezone):

- **Weekdays:** after 6pm only
- **Weekends:** all day

This ensures dependency PRs are never opened during working hours and cluster changes
from auto-merged upgrades land at low-traffic times.

---

## Auto-merge Rules

### What is auto-merged (no human required)

| Update type | Rationale |
|-------------|-----------|
| **Patch** (`1.2.3 → 1.2.4`) | Backwards-compatible bug fixes. Low risk by semver contract. |
| **Digest** (Docker image SHA bump) | Same tag, updated image content. Typically security patches. |
| **GitHub Actions** (minor + patch) | Action version bumps. No cluster impact. |

These update types proceed through CI validation and are squash-merged automatically by the
auto-merge workflow (ADR-009) once all checks pass.

### What requires manual review

| Update type | Rationale |
|-------------|-----------|
| **Minor** (`1.2.x → 1.3.x`) | May introduce new default behaviours, configuration schema changes, or feature flags that need review. |
| **Major** (`1.x → 2.x`) | Breaking changes expected. Requires reading the changelog and testing. |
| **Any `kubernetes`, `kube`, or `k3s` package** | Kubernetes and k3s upgrades affect the control plane, etcd, and every workload. Always reviewed regardless of version bump size. |

Renovate opens the PR but it sits open until manually reviewed and merged.

---

## Grouping Strategy

Related packages that must upgrade together are grouped into a single PR to prevent
partial upgrades that cause version skew:

| Group | Packages | Reason |
|-------|----------|--------|
| `flux2` | fluxcd/flux2 | Flux controllers and CRDs must stay in sync |
| `kube-prometheus-stack` | kube-prometheus-stack, prometheus, grafana | Subcharts must stay aligned with the parent chart |
| `cert-manager` | jetstack/cert-manager | CRD controller and CRDs must upgrade together |
| `media-stack images` | docker/compose/media-stack.yml | Grouped to reduce PR noise |
| `monitoring-exporters images` | docker/compose/monitoring-exporters.yml | Grouped to reduce PR noise |
| `proxy-stack images` | docker/compose/proxy-stack.yml | Grouped to reduce PR noise |
| `platform-stack images` | docker/compose/platform-stack.yml | Grouped to reduce PR noise |
| `github actions` | all GitHub Actions | Auto-mergeable as a group |

---

## PR Limits

To prevent Renovate from flooding the repository with PRs during a large batch update:

- **Max concurrent open PRs:** 5
- **Max PRs opened per hour:** 2

These limits keep the PR queue manageable for a solo operator.

---

## Safety Net

Even with auto-merge enabled for patches, every update goes through:

1. **`kustomize build`** — confirms manifests are structurally valid
2. **`kubeconform`** — confirms resources match the Kubernetes API schema
3. **`pluto`** — confirms no deprecated APIs are introduced
4. **Chart version existence check** — confirms the chart version actually exists in the Helm repo
5. **`flux diff`** — shows exactly what will change in the cluster before merge
6. **Post-merge health check** — confirms all kustomizations remain Ready after Flux reconciles

A patch update that somehow breaks a kustomize build or introduces a schema violation will
be blocked by CI before it reaches the cluster.

---

## HelmRelease Remediation

All HelmReleases are configured with automatic rollback on upgrade failure:

```yaml
upgrade:
  remediation:
    retries: 3
    strategy: rollback
```

If a chart upgrade fails in the cluster — even after passing CI — Flux rolls back to the
previous Helm release revision automatically. This means a bad patch update landing at
midnight does not require manual intervention to recover.

---

## Rolling Update Strategy

Key stateful applications are configured with zero-downtime rolling updates:

```yaml
strategy:
  type: RollingUpdate
  rollingUpdate:
    maxUnavailable: 0
    maxSurge: 1
```

`maxUnavailable: 0` means the old pod stays running until the new pod passes its readiness
probe. `maxSurge: 1` allows one extra pod during the transition. Together this guarantees
no downtime during a chart upgrade for the following applications:

| Application | Why rolling update matters |
|-------------|---------------------------|
| Authentik | SSO provider — all apps depend on it for authentication |
| Nextcloud | File storage — users may be mid-operation during an upgrade |
| Immich | Photo library — long-running background jobs |

Applications not listed (n8n, Vaultwarden) run as single replicas on NFS storage.
`maxSurge: 1` would require two pods writing to the same PVC simultaneously, which is
unsafe with `ReadWriteOnce` access mode. These apps tolerate a brief restart window.

---

## Minimum Release Age

Patch and digest updates are not auto-merged immediately upon publication. A 3-day
`minimumReleaseAge` is enforced before auto-merge is eligible:

```json
"minimumReleaseAge": "3 days"
```

**Why:** A breaking patch is possible. A 3-day window allows the community to discover
and report regressions before they land in the cluster. Critical security patches can
be triggered immediately via the Renovate Dependency Dashboard if needed.

---

## Docker Host Health Check

After deploying Docker stacks via Ansible, the deploy playbook waits 10 seconds and
then verifies no containers are in a restart loop or exited with a non-zero status:

```bash
docker ps -a | grep -Ev 'Up|Exited (0)'
```

If any container is unhealthy the playbook fails, surfacing the issue immediately
rather than silently leaving a broken stack running.

---

## Kustomize Path Drift Detection

The validate CI job includes a check that compares the `path:` entries in
`clusters/prod/infrastructure.yaml` and `clusters/prod/apps.yaml` against the
`KUSTOMIZE_PATHS` list in the validate workflow. If a new Flux kustomization is added
to the infrastructure but its path is not added to the workflow, CI fails with:

```
ERROR: The following Flux kustomization paths are not validated in this workflow:
platform/networking/new-component
Add them to the KUSTOMIZE_PATHS list in this workflow.
```

This prevents the class of error where a new component is deployed via Flux but its
manifests are never validated in CI.

---

## Manual Override

To force Renovate to open a specific PR immediately (outside schedule):

Use the **Renovate Dependency Dashboard** issue in the repository. Check the box next to
the dependency you want to update and Renovate will open the PR on its next run.

To skip a specific update entirely, add to `renovate.json`:

```json
{
  "packageRules": [
    {
      "matchPackageNames": ["some/package"],
      "enabled": false
    }
  ]
}
```

---

## Consequences

### Positive

- Patch-level security fixes land within 3-4 days of publication with zero manual effort (3-day minimum age + next scheduled Renovate run)
- Minor and major updates are surfaced automatically but never applied without review
- Kubernetes-related packages are always gated regardless of version bump size
- Upgrade history is fully captured in `git log main` via squash commits
- No manual dependency tracking required

### Negative

- Renovate PRs can accumulate if minor/major updates are not reviewed regularly
- The 6pm schedule means a critical security patch published at 8am won't open a PR until evening — for urgent patches, trigger manually via the Dependency Dashboard
- Grouped PRs (e.g. kube-prometheus-stack) can be large and harder to review than individual bumps

---

## Related

- ADR-009 — PR-Based Validation Pipeline (the CI pipeline that gates all upgrades)
- `.github/workflows/auto-merge.yml` — auto-merge workflow
- `.github/workflows/validate.yml` — validation pipeline
- `renovate.json` — full Renovate configuration
