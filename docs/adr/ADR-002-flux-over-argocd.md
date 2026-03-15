
# ADR-002 — FluxCD over ArgoCD

**Status:** Accepted
**Date:** 2026-01-15
**Deciders:** Platform team

---

## Context

The platform requires a GitOps controller to continuously reconcile cluster state from a Git repository. The two dominant options in the Kubernetes ecosystem are FluxCD and ArgoCD.

## Decision

**FluxCD was selected.**

## Rationale

| Criterion | FluxCD | ArgoCD |
|-----------|--------|--------|
| Architecture | Multiple small controllers | Monolithic application server |
| UI | None (CLI + Grafana dashboards) | Built-in web UI |
| Resource usage | Low (~100MB RAM) | Higher (~500MB RAM baseline) |
| SOPS native decryption | Yes (built-in) | No (requires plugin) |
| Helm support | Yes (Helm Controller) | Yes |
| Kustomize support | Yes | Yes |
| Multi-tenancy | Via namespaces | Built-in RBAC UI |
| CNCF graduated | Yes | Yes |

**Key deciding factors for this platform:**

1. **SOPS native support.** Flux has first-class native support for SOPS decryption. ArgoCD requires a custom plugin to achieve equivalent functionality. Given that SOPS + age is the chosen secrets strategy, Flux is the natural pairing.

2. **Lightweight architecture.** Flux's controller-per-concern model (source, kustomize, helm, notification) uses fewer resources than ArgoCD's monolithic application server. On a three-node homelab, this matters.

3. **No UI dependency.** The platform uses Grafana for operational visibility. A separate ArgoCD UI would be redundant infrastructure. Flux integrates with Grafana through its Prometheus metrics.

4. **Git repository is the UI.** In a single-operator platform, the Git repository and `flux` CLI provide sufficient operational visibility. ArgoCD's UI is most valuable for teams with multiple engineers reviewing deployment state.

## Consequences

- All cluster state is managed declaratively through `Kustomization` and `HelmRelease` resources.
- No web UI for Flux. Operators use `flux get all`, `flux logs`, and Grafana dashboards for visibility.
- SOPS decryption is configured per-Kustomization via `spec.decryption`.
- Flux bootstraps by committing manifests into the repository. This means the Git repository contains Flux's own installation manifests, which is a desirable property.

---
