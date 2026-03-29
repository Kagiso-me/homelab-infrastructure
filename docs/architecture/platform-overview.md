# Platform Overview

## Purpose

This repository describes a homelab Kubernetes platform built for personal learning, service hosting, and infrastructure experimentation. The primary operational target is a **full cluster rebuild in under 2 hours** from bare OS — ensuring that hardware failure or catastrophic misconfiguration is a recoverable event rather than a crisis.

All platform state is expressed as code in this repository. A new node can join, FluxCD can reconcile, and services restore from backup without manual intervention beyond initial node provisioning.

---

## Design Principles

| Principle | Description |
|---|---|
| **GitOps-first** | All cluster state — manifests, Helm releases, secrets references, and configuration — lives in Git. No `kubectl apply` outside of bootstrap. FluxCD is the sole agent of change. |
| **Everything encrypted** | Secrets are never stored in plaintext in Git. SOPS with age encryption is used for all sensitive values. Decryption keys are kept off-cluster and injected only at bootstrap. |
| **Immutable infrastructure** | Nodes are not patched in place beyond OS security updates. Cluster upgrades are performed via system-upgrade-controller Plans. Configuration drift is treated as a defect, not a norm. |
| **Observability-first** | Metrics, logs, and alerts are considered load-bearing infrastructure, not an afterthought. Every platform component exposes a ServiceMonitor. Alertmanager routes to Slack and a webhook endpoint. |
| **Rebuild target < 2 hours** | Every architectural decision is weighed against whether it makes the cluster easier or harder to rebuild. Complexity that cannot be recovered automatically is minimised. |

---

## Component Table

| Layer | Component | Purpose | Version Pinned |
|---|---|---|---|
| **Cluster** | k3s | Lightweight Kubernetes distribution | Yes |
| **GitOps** | FluxCD v2 | Continuous reconciliation from Git | Yes |
| **Secrets** | SOPS + age | Encrypted secrets in Git | Yes |
| **Networking — LB** | MetalLB | Bare-metal LoadBalancer implementation | Yes |
| **Networking — Ingress** | Traefik | Ingress controller and reverse proxy | Yes |
| **Certificates** | cert-manager | Let's Encrypt HTTP-01 certificate issuance | Yes |
| **Storage** | NFS Subdir External Provisioner | Dynamic PVC provisioning via TrueNAS NFS | Yes |
| **Metrics** | kube-prometheus-stack (Prometheus + Grafana) | Cluster metrics collection and dashboards | Yes |
| **Logs** | Loki + Promtail | Log aggregation and shipping | Yes |
| **Alerting** | Alertmanager | Alert routing to Slack and webhook | Yes (bundled with kube-prometheus-stack) |
| **Backups** | Velero | Kubernetes resource and volume snapshots | Yes |
| **Backup storage** | MinIO on TrueNAS | S3-compatible local backup target | Yes |
| **Backup offsite** | Backblaze B2 | Nightly offsite copy of Velero backups | N/A (external) |
| **Upgrades** | system-upgrade-controller | Automated, rolling k3s node upgrades | Yes |
| **Helm charts** | kagiso-me/charts | First-party charts for infrastructure-critical workloads; published to GitHub Pages + Artifact Hub | Yes |

---

## Dependency Diagram

The diagram below shows the order in which platform layers must be healthy before the next layer can function. Arrows denote "must be ready before".

```
+------------------+
|   Networking     |  MetalLB (IP pool), Traefik (ingress), cert-manager (TLS)
|  MetalLB         |
|  Traefik         |
|  cert-manager    |
+--------+---------+
         |
         v
+------------------+
|    Security      |  SOPS/age decryption, sealed namespaces, RBAC policies
|  SOPS + age      |
|  FluxCD          |
+--------+---------+
         |
         v
+------------------+
|   Namespaces     |  Platform namespaces created and labelled before workloads
|  flux-system     |
|  monitoring      |
|  storage         |
|  velero          |
+--------+---------+
         |
    +----+----+
    |         |
    v         v
+-------+  +-------+
| Obser-|  |Storage|  kube-prometheus-stack, Loki, Alertmanager
| vabil.|  |       |  NFS StorageClass (nfs-truenas), TrueNAS NFS server
+---+---+  +---+---+
    |           |
    +----+-------+
         |
         v
+------------------+
|    Backup        |  Velero -> MinIO -> Backblaze B2
+--------+---------+
         |
         v
+------------------+
|  Applications    |  User-facing workloads reconciled by FluxCD
+------------------+
```

---

## Key Design Decisions

Significant architectural choices are captured as Architecture Decision Records (ADRs) in [`docs/adr/`](../adr/). Each ADR documents the context, the decision made, alternatives considered, and the consequences accepted.

| ADR | Title | Status |
|---|---|---|
| [ADR-006](../adr/ADR-006-ha-control-plane.md) | HA Control-Plane (3-Node etcd Cluster) | Accepted |
| [ADR-007](../adr/ADR-007-self-hosted-runners.md) | Self-Hosted GitHub Actions Runners | Accepted |

---

## Known Constraints

| Constraint | Detail |
|---|---|
| **Single-instance stateful workloads** | PostgreSQL, Redis, and some observability paths still trade availability for simplicity. A node loss is survivable at the control-plane level, but these workloads can still cause partial service degradation. |
| **Homelab hardware** | Nodes are consumer or small-form-factor machines. No redundant power, no ECC memory. Hardware failure is a realistic failure mode. |
| **Homelab HA, not enterprise HA** | The control-plane now uses 3-node embedded etcd with a kube-vip API endpoint, but several data services remain single-instance. |
| **Single ISP / site** | There is no multi-site redundancy. A premises outage takes down all services. |
| **No synthetic monitoring** | External uptime checks and end-to-end synthetic probes are not currently implemented. |
| **No distributed tracing** | Tracing (e.g., Jaeger, Tempo) is not deployed. Observability is metrics and logs only. |
| **Domain dependency** | Public ingress depends on `kagiso.me` DNS and Let's Encrypt reachability for certificate issuance and renewal. |

