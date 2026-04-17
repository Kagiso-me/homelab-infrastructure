# 2026-03 — DEPLOY: Add Velero metrics section to backup overview dashboard

**Operator:** Kagiso
**Type:** `DEPLOY`
**Components:** Velero · Grafana · Prometheus · backup dashboard
**Commit:** —
**Downtime:** None

---

## What Changed

Extended the backup overview Grafana dashboard with a Velero section showing backup schedule status, last backup timestamp, backup duration, and backup size over time.

---

## Why

Velero was running and taking backups, but there was no visibility into whether they were succeeding consistently. "Backups are configured" is not the same as "backups are working". The Grafana section surfaces Velero's built-in Prometheus metrics so backup health is visible at a glance without running `velero backup get` manually.

---

## Details

- Velero metrics endpoint: `velero-service:8085/metrics` — already scraped by Prometheus via ServiceMonitor
- **Panels added**:
  - Last successful backup age (alert if > 25h)
  - Backup duration histogram (p50, p95)
  - Backup size by schedule (bytes)
  - Backup failure count (last 7 days)
  - Schedule status table (name, last run, status)
- Dashboard updated as ConfigMap in `platform/observability/grafana-dashboards/`

---

## Outcome

- Velero backup health visible in Grafana ✓
- Alert configured if last backup > 25h ✓
- First backup failure would now appear as a red panel ✓

---

## Related

- Grafana dashboards ConfigMap: `platform/observability/grafana-dashboards/`
- Velero HelmRelease: `platform/backup/velero/helmrelease.yaml`
