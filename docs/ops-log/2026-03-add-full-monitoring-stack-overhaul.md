# 2026-03 — DEPLOY: Add full monitoring stack overhaul

**Operator:** Kagiso
**Type:** `DEPLOY`
**Components:** kube-prometheus-stack · Prometheus · Grafana · node-exporter · kube-state-metrics
**Commit:** —
**Downtime:** None (replaced Docker-based stack with in-cluster)

---

## What Changed

Replaced the Docker Compose-based monitoring stack (Prometheus + Grafana on varys) with `kube-prometheus-stack` running natively in the k3s cluster. This brings Prometheus, Grafana, Alertmanager, node-exporter, kube-state-metrics, and all default Kubernetes recording rules in a single HelmRelease.

---

## Why

The Docker-based monitoring stack on varys was a leftover from before the cluster existed. It scraped k3s API endpoints externally, which meant it missed pod-level metrics, couldn't use ServiceMonitor CRDs, and required manual target management. Running monitoring in-cluster gives native Kubernetes service discovery, PodMonitor/ServiceMonitor support, and proper RBAC-scoped scraping.

Also: varys is being transitioned to a Proxmox host. Monitoring shouldn't depend on a host that's about to be repurposed.

---

## Details

- **Chart**: `kube-prometheus-stack` from `prometheus-community` Helm repo, version pinned
- **Prometheus**: 15-day retention, 20Gi PVC on `local-path` (node-local, not NFS — see Prometheus storage ADR)
- **Grafana**: enabled, persistence on NFS, admin credentials from SOPS secret
- **node-exporter**: DaemonSet on all nodes, scrapes system-level metrics
- **kube-state-metrics**: scrapes Kubernetes object state (Deployments, Pods, HelmReleases)
- **Default dashboards**: Kubernetes / Overview, Node Exporter Full, Flux dashboards added via ConfigMap
- **Removed**: Docker Compose prometheus + grafana stack on varys

---

## Outcome

- Full in-cluster monitoring stack running ✓
- All k3s nodes, pods, and workloads visible in Grafana ✓
- Docker monitoring stack on varys decommissioned ✓
- Zero metric gaps during transition ✓

---

## Related

- kube-prometheus-stack HelmRelease: `platform/observability/kube-prometheus-stack/helmrelease.yaml`
- ADR-009 (Prometheus storage): `docs/adr/ADR-009-prometheus-local-storage.md`
