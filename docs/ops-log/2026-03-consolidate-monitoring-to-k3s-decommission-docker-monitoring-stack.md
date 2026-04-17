# 2026-03 — DEPLOY: Consolidate monitoring to k3s, decommission Docker monitoring stack

**Operator:** Kagiso
**Type:** `DEPLOY`
**Components:** Prometheus · Grafana · varys · k3s · Docker Compose
**Commit:** —
**Downtime:** ~5 minutes (Grafana unavailable during cutover)

---

## What Changed

Decommissioned the Docker Compose-based Prometheus and Grafana stack running on `varys`. All monitoring now runs in-cluster via `kube-prometheus-stack`. Grafana dashboards migrated, persistent data discarded (metric history reset to zero).

---

## Why

Running two monitoring stacks (Docker on varys + kube-prometheus-stack in cluster) was creating confusion — alerts could come from either, dashboards showed different data, and the Docker stack had no visibility into pod-level metrics. The kube-prometheus-stack is strictly superior for cluster monitoring. Keeping the Docker stack alongside it served no purpose.

Metric history was not worth preserving — the Docker stack had incomplete data and the in-cluster stack was the source of truth going forward.

---

## Details

- Stopped and removed `monitoring` Docker Compose stack on varys
- Removed `prometheus` and `grafana` services from varys Compose files
- Grafana dashboards re-imported from JSON exports into in-cluster Grafana (homelab overview, node exporter, Flux, Velero, CrowdSec)
- Prometheus scrape targets previously on the Docker stack (TrueNAS, varys host metrics) added as static targets to in-cluster Prometheus
- varys freed of ~800MB RAM previously used by Docker monitoring

---

## Outcome

- Single monitoring stack — all in k3s ✓
- ~800MB RAM freed on varys ✓
- All dashboards available in in-cluster Grafana ✓
- External scrape targets migrated ✓

---

## Related

- kube-prometheus-stack: `platform/observability/kube-prometheus-stack/`
- Monitoring stack overhaul: `docs/ops-log/2026-03-add-full-monitoring-stack-overhaul.md`
