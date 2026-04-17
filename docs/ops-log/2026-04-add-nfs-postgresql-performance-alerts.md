# 2026-04 — DEPLOY: Add NFS PostgreSQL performance alerts

**Operator:** Kagiso
**Type:** `DEPLOY`
**Components:** Prometheus · Alertmanager · PostgreSQL · NFS · TrueNAS
**Commit:** —
**Downtime:** None

---

## What Changed

Added Prometheus alerting rules targeting PostgreSQL-over-NFS performance degradation: alerts fire when NFS I/O latency exceeds thresholds that historically precede PostgreSQL connection timeouts.

---

## Why

The shared PostgreSQL instance runs on NFS-backed storage (TrueNAS). Any NFS hiccup causes PostgreSQL to stall — connection queues build up and apps start returning 503s. Without specific alerting, the first sign of trouble was app errors, not an infrastructure alert. By the time you notice in Grafana, several minutes of errors have already accumulated.

The new alerts fire early — before apps are affected — giving time to investigate TrueNAS health before it cascades.

---

## Details

- **Alert 1**: `NfsHighLatency` — fires if NFS I/O wait > 50ms for 5 minutes
- **Alert 2**: `PostgresNfsStall` — fires if PostgreSQL connection wait time > 2s
- **Alert 3**: `PostgresConnectionPoolNearLimit` — fires if active connections > 80% of `max_connections`
- All alerts route to Discord via Alertmanager webhook
- Runbook links added to alert annotations pointing at TrueNAS health check procedure

---

## Outcome

- Alerts defined and reconciled by Flux ✓
- Test alert fired and appeared in Discord ✓
- No false positives in first 48h of monitoring ✓

---

## Related

- Alert rules: `platform/monitoring/prometheus/rules/nfs-postgres.yaml`
- Alertmanager config: `platform/monitoring/prometheus/alertmanager-config.yaml`
