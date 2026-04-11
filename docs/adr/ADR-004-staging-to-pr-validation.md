# ADR-004 — Staging Cluster Decommission in Favour of PR-Based Validation

**Status:** Superseded by ADR-009
**Date:** 2026-03-28
**Deciders:** Kagiso

---

## Context

The original CI/CD model used a dedicated staging environment to gate production deployments.
A single-node k3s cluster ran as a Proxmox VM (`staging-k3s`, 10.0.10.31) on the NUC that
later became the Docker host (`bronn`, 10.0.10.20).

The promotion pipeline worked as follows:

1. Changes merged to `main`
2. Flux reconciled `main` on the staging cluster
3. A post-merge GitHub Actions job checked that the staging cluster was healthy
4. If healthy, `main` was automatically merged into a `prod` branch
5. Flux on the production cluster reconciled from `prod`

The intent was to catch breakages in a lower-risk environment before they reached production.

---

## Why it failed

**Staging gave false confidence.**

Only a small subset of the production workload was ever deployed to staging. The platform
layer (Traefik, cert-manager, Flux itself) was present, but most application HelmReleases
(Nextcloud, Immich, Authentik, n8n) were never deployed there — maintaining their secrets
and dependencies in a second environment was too much overhead for a single operator. A
passing staging health check meant "Traefik is up" — nothing more.

Bugs that actually reached production were not caught by staging. They were caught by Flux
failing to reconcile a HelmRelease, or by a broken manifest that only failed when applied
against the real CRD versions running in production.

**Staging required constant maintenance.**

The staging cluster diverged from production over time. Proxmox VM snapshots occasionally
left the k3s node in an inconsistent state. When staging was broken (not uncommon), every
PR was held up waiting for a staging cluster that was failing for reasons unrelated to the
change being tested. The maintenance cost was real; the safety benefit was marginal.

**Proxmox was decommissioned.**

The NUC running the Proxmox hypervisor (and the staging VM) was repurposed as a bare-metal
Docker host (`bronn`). The `staging-k3s` VM no longer exists. This forced the decision.

---

## Decision

Decommission the staging cluster and the `main` → `prod` promotion pipeline.

Replace it with a PR-based static validation pipeline that validates every manifest before
it merges, and a post-merge health check against the production cluster directly.

The full design of the replacement is documented in **ADR-009**.

---

## Key trade-off

The staging model provided an integration environment — changes were applied to a real
(if limited) cluster before production. The PR validation model provides broader coverage
(every file validated, not just deployed ones) but validates against schemas and cluster
state rather than by actually applying the change.

The bet is that schema validation + `flux-local diff` + a post-merge production health
check catches more real errors than a staging cluster that only ran a fraction of the
production workload. In practice this has proven correct — no production outage has been
caused by a change that passed PR validation since the migration.

---

## Consequences

- The `prod` branch is removed. `main` is the single source of truth for the production cluster.
- Flux on production reconciles directly from `main`.
- No staging secrets, no staging kubeconfig, no staging-specific manifests to maintain.
- A broken manifest is caught at PR time by `kubeconform` and `flux-local diff`, not after merge.
- The post-merge health check runs against production — if it fails, the cluster is already
  affected. This is the honest trade-off accepted by removing staging.
