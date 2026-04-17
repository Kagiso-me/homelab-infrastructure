# 2026-03 — DEPLOY: Overhaul Grafana dashboards and add Backblaze B2 monitoring

**Operator:** Kagiso
**Type:** `DEPLOY`
**Components:** Grafana · Backblaze B2 · Prometheus · dashboards
**Commit:** —
**Downtime:** None

---

## What Changed

Rebuilt the main Grafana homelab overview dashboard from scratch and added Backblaze B2 bucket monitoring (backup storage usage and cost estimates).

---

## Why

The original overview dashboard was assembled quickly and showed metrics without context — raw numbers, no thresholds, no colour coding. After a few weeks of use, the gaps became clear: you couldn't tell at a glance if something was wrong or just unusual. The rebuild applies consistent status colouring (green/amber/red), adds sparklines for trend visibility, and organises panels by concern (cluster health, storage, backups, network).

Backblaze B2 monitoring was added because backup storage costs were completely invisible — the bucket was growing and there was no way to forecast spend without logging into the B2 console.

---

## Details

**Dashboard overhaul:**
- Rebuilt as provisioned ConfigMap (not manually imported — survives Grafana restarts)
- Consistent colour thresholds across all stat panels
- Added: cluster health row, storage usage row, backup status row, network row
- Removed: stale panels from Docker-era monitoring

**Backblaze B2 monitoring:**
- B2 doesn't have a native Prometheus exporter — used `backblaze-b2-exporter` (small Python script running as CronJob every hour)
- Exports: bucket size (bytes), file count, last modified timestamp, estimated monthly cost at current rate
- Panels: storage used over time, cost forecast, backup count trend

---

## Outcome

- New overview dashboard deployed as ConfigMap ✓
- B2 CronJob exporter running, metrics in Prometheus ✓
- Backup storage cost visible in Grafana ✓

---

## Related

- Dashboard ConfigMap: `platform/observability/grafana-dashboards/homelab-overview.json`
- B2 exporter CronJob: `platform/observability/b2-exporter/`
