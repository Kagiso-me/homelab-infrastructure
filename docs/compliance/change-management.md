# Change Management Process

## Document Control

| Field        | Value             |
|--------------|-------------------|
| Version      | 1.0               |
| Date         | 2026-03-14        |
| Status       | Active            |
| Owner        | Platform Engineer |
| Review Cycle | Quarterly         |

---

## 1. Purpose and Scope

This document defines the change management process for the homelab Kubernetes infrastructure. It establishes how changes are proposed, reviewed, tested, applied, and recorded to maintain a stable, auditable, and recoverable environment.

**In scope:**
- All changes to Kubernetes workloads, configuration, and cluster-level resources
- Platform upgrades (k3s, Helm charts, container images)
- Infrastructure changes (node provisioning, network configuration, TrueNAS configuration)
- Secrets, RBAC, and security configuration changes
- Changes to the GitOps repository structure and FluxCD configuration

**Out of scope:**
- Read-only operations (kubectl get, describe, logs)
- Grafana dashboard changes that do not affect alerting rules
- TrueNAS UI changes that do not affect NFS exports or dataset configuration consumed by Kubernetes

---

## 2. Guiding Principles

1. **Git is the source of truth.** All infrastructure state is defined in the Git repository. The running cluster state should always converge to what is declared in Git.
2. **No direct cluster mutations.** Changes to the cluster must not be made by running `kubectl apply` or `helm install` commands directly in production without going through the GitOps pipeline, except in documented emergencies.
3. **Every change is reviewable.** Git history provides a complete, timestamped record of all changes. Commit messages explain the intent; PRs (even self-reviewed) provide a record of reasoning.
4. **Changes are tested before merging.** CI checks (kubeconform, flux-local) must pass before any change reaches the `main` branch.
5. **Rollback is always possible.** Because Git is the source of truth, reverting a change is a git revert followed by a Flux reconciliation.

---

## 3. Change Categories

### Category 1 — Standard GitOps Changes

**Definition:** Any change to Kubernetes manifests, Helm chart values, Kustomization overlays, or FluxCD configuration that flows through the normal GitOps pipeline.

**Examples:**
- Updating a container image tag in a Deployment
- Adding a new namespace or application
- Modifying resource requests/limits
- Updating Helm chart values
- Adding or modifying RBAC resources

**Process:**
1. Create a feature branch from `main`.
2. Make changes to relevant YAML files.
3. Run local validation: `kubeconform`, `flux build kustomization`, `helm template`.
4. Open a Pull Request against `main`.
5. CI checks must pass (kubeconform + flux-local lint).
6. Self-review: confirm intent matches implementation; confirm no unintended side effects.
7. Merge to `main`.
8. FluxCD automatically reconciles the change to the cluster within the configured interval (default: 10 minutes) or via `flux reconcile`.
9. Verify workload health post-apply: `kubectl get pods -n <namespace>`.

**Approval:** Self-reviewed. Peer review is the intent where a second reviewer is available (e.g., for significant changes), but is not currently enforced in this single-operator environment.

---

### Category 2 — Platform Upgrades

**Definition:** Upgrades to cluster-level components: k3s version, system-level Helm releases (Traefik, cert-manager, Velero, kube-prometheus-stack), or CNI.

**Examples:**
- k3s version upgrade (e.g., v1.29.x → v1.30.x)
- Traefik Helm chart upgrade
- cert-manager CRD upgrade

**Process:**
1. Review the upstream release notes and changelog for breaking changes.
2. For k3s upgrades: create a `Plan` object for `system-upgrade-controller` targeting the desired version. Apply via GitOps.
3. For Helm upgrades: update the chart version in the HelmRelease manifest. Open a PR as per Category 1.
4. Monitor the upgrade via: `kubectl get plans -n system-upgrade`, `flux get helmreleases -A`.
5. Verify all Tier 1 services are healthy post-upgrade.
6. Record the upgrade in the Git commit message with the before/after version.

**Approval:** Self-reviewed. Platform upgrades are conducted during the scheduled maintenance window (Sunday 02:00–04:00 SAST) where possible.

**Rollback:** Revert the HelmRelease or Plan manifest in Git; Flux reconciles back to the previous version. Note: k3s downgrades are not officially supported; a snapshot-based restore may be required for failed k3s upgrades.

---

### Category 3 — Infrastructure Changes

**Definition:** Changes to the underlying compute, network, or storage infrastructure that are not managed directly by Kubernetes manifests.

**Examples:**
- Adding or replacing a cluster node
- Changing TrueNAS NFS export configuration
- Modifying network/VLAN configuration
- Updating homelab router/firewall rules

**Process:**
1. Document the intended change in a Git commit or PR description (even if the change itself is made outside of Git, e.g., in TrueNAS UI).
2. Notify any dependent services of the pending change.
3. Apply the change during the maintenance window.
4. Verify cluster health after the change: `kubectl get nodes`, `kubectl get pods -A`.
5. Update relevant architecture documentation in `docs/architecture/`.
6. Commit documentation changes to Git.

**Approval:** Self-reviewed. Infrastructure changes with potential cluster-wide impact (e.g., changing the NFS server IP) require extra care and should be tested in a controlled manner where possible.

---

### Category 4 — Emergency Changes

**Definition:** Changes that must be applied immediately outside of the normal GitOps pipeline due to a live incident. These are exceptional and must be documented after the fact.

**Examples:**
- Scaling down a misbehaving deployment to stop an outage
- Applying a one-line secret rotation during an incident
- Force-deleting a stuck namespace or pod

**Process:**
1. Apply the minimum necessary change directly via `kubectl` to stabilise the situation.
2. Record what was changed, why, and when in `docs/compliance/incident-log.md`.
3. Within 24 hours of the incident, create a Git commit that reflects the emergency change (so the Git state matches the cluster state).
4. Review whether the emergency change reveals a gap in runbooks, alerting, or policy, and remediate accordingly.

**Approval:** No pre-approval required for emergency changes. Post-hoc documentation is mandatory.

> Emergency changes that bypass GitOps create a state drift between Git and the cluster. Flux will attempt to revert un-reconciled changes on its next reconciliation cycle. Use `flux suspend kustomization <name>` to pause reconciliation during an emergency if needed, and resume immediately after the emergency is resolved and Git is updated.

---

## 4. CI Validation Checks

All PRs targeting `main` must pass the following automated checks before merge:

| Check                   | Tool                  | What It Validates                                           |
|-------------------------|-----------------------|-------------------------------------------------------------|
| Kubernetes manifest lint| `kubeconform`         | Manifests conform to Kubernetes API schema for target version |
| Flux kustomization build| `flux build ks`       | Kustomization overlays render correctly without errors       |
| Helm template render    | `helm template`       | Helm chart values produce valid Kubernetes YAML              |
| SOPS encryption check   | Custom script / CI    | No plaintext secrets committed to the repository            |

### Staging Cluster (Intent)

A staging cluster is not currently provisioned. The intent is to validate significant changes against a staging environment before applying to the production homelab cluster. Until a staging cluster is available, CI validation checks serve as the primary pre-merge gate.

---

## 5. Rollback Procedure

Rollback is the primary recovery mechanism for a failed change.

### Standard Rollback (GitOps)

1. Identify the last known good commit in Git: `git log --oneline`
2. Revert the offending commit: `git revert <commit-sha>`
3. Push the revert commit to `main`.
4. Flux will automatically reconcile the reverted state to the cluster.
5. Optionally trigger immediate reconciliation: `flux reconcile kustomization flux-system --with-source`

### Flux Suspend (Emergency Pause)

To stop Flux from applying changes while investigating an issue:

```bash
flux suspend kustomization <kustomization-name>
```

This does not revert applied changes — it only stops future reconciliation. Resume with:

```bash
flux resume kustomization <kustomization-name>
```

### Helm Release Rollback

For a failed Helm chart upgrade:

```bash
helm rollback <release-name> -n <namespace>
```

Note: If Flux is managing the HelmRelease, a `helm rollback` will be reverted by Flux on the next reconciliation unless the HelmRelease manifest in Git is also reverted.

---

## 6. Change Log

**Git history is the authoritative change log for this infrastructure.**

Every merge to `main` represents a change record with:
- Timestamp (Git commit timestamp)
- Author (committer identity)
- Description (commit message)
- Diff (exact files and lines changed)

Commit messages must follow the format:

```
<type>: <short summary>

<optional body explaining why the change was made, not just what>

Refs: <issue number, ADR reference, or incident reference if applicable>
```

Where `<type>` is one of: `feat`, `fix`, `chore`, `upgrade`, `docs`, `refactor`, `revert`, `security`.

Additional context for significant changes (architectural decisions, rationale for non-obvious choices) is documented in `docs/adr/` as Architecture Decision Records.

---

## 7. Prohibited Changes

The following actions are prohibited without explicit documented justification:

| Prohibited Action                                              | Reason                                                         |
|----------------------------------------------------------------|----------------------------------------------------------------|
| `kubectl apply -f` in production without a corresponding Git commit | Bypasses GitOps; creates state drift; not auditable      |
| `helm install` or `helm upgrade` directly without updating HelmRelease in Git | Same as above                               |
| Committing plaintext secrets to the Git repository             | Security violation; see Security Policy                       |
| Using `latest` image tags in manifests                         | Non-reproducible deployments; prevents reliable rollback      |
| Deleting Velero backups manually before TTL expiry             | Violates backup retention policy                              |
| Granting wildcard ClusterRole permissions                      | Violates least-privilege RBAC policy; see Security Policy     |
| Applying changes to `kube-system` via Flux or manual kubectl without documented justification | High blast radius; can break the cluster |

Violations of these prohibitions must be documented in `docs/compliance/incident-log.md` with corrective actions.

---

## 8. Policy Compliance and Review

This process is reviewed quarterly. Adherence is validated by reviewing:
- Git commit history for evidence of direct `kubectl apply` bypasses
- Alertmanager history for incidents caused by undocumented changes
- Flux reconciliation logs for unexpected state drift

| Version | Date       | Author            | Summary of Changes     |
|---------|------------|-------------------|------------------------|
| 1.0     | 2026-03-14 | Platform Engineer | Initial document       |
