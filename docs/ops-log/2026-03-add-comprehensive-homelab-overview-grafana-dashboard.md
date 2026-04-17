# 2026-03 — DEPLOY: Add comprehensive homelab overview Grafana dashboard

**Operator:** Kagiso
**Type:** `DEPLOY`
**Components:** Grafana · Prometheus · kube-state-metrics · dashboard
**Commit:** —
**Downtime:** None

---

## What Changed

Created and deployed the main homelab overview Grafana dashboard as a provisioned ConfigMap. This is the first-open dashboard showing the state of the entire homelab at a glance.

---

## Why

Before this dashboard, checking cluster health meant opening multiple panels across multiple dashboards. The overview consolidates the most important signals — pod health, node resources, backup status, storage usage, network — into a single page that can be read in under 10 seconds.

---

## Details

**Dashboard sections:**
- **Cluster health row**: pod running/total, Flux kustomizations ready/total, node count
- **Node resources row**: CPU%, memory%, disk I/O per node — sparkline + current value
- **Storage row**: TrueNAS pool usage % with colour thresholds (warn at 75%, crit at 90%)
- **Backup row**: last Velero backup age, last etcd snapshot age, Docker Appdata backup age
- **Network row**: MikroTik WAN latency, firewall hit rate, CrowdSec active bans
- **Services row**: up/down status tiles for all external services

**Implementation:**
- Dashboard JSON stored in ConfigMap, provisioned into Grafana at startup
- Data sources: Prometheus (cluster + host metrics), Loki (log-based metrics)
- Refresh: 30s auto-refresh

---

## Outcome

- Overview dashboard deployed and accessible in Grafana ✓
- All sections populated with live data ✓
- Set as Grafana home dashboard ✓

---

## Related

- Dashboard ConfigMap: `platform/observability/grafana-dashboards/homelab-overview.json`
