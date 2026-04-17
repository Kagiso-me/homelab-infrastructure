# 2026-03 — DEPLOY: Metrics, dashboards, backup, and etcd snapshot offloading

**Operator:** Kagiso
**Type:** `DEPLOY`
**Components:** Prometheus · Grafana · Velero · etcd · Backblaze B2
**Commit:** —
**Downtime:** None

---

## What Changed

Large batch deployment wiring together the observability and backup layers: Prometheus scraping, initial Grafana dashboards, Velero for cluster backup, and automated etcd snapshot offloading to Backblaze B2.

---

## Why

The cluster had applications running but no observability and no backup. This batch addressed both in a single pass: metrics first (you can't know if a backup succeeded without metrics), then backup, then etcd snapshots for disaster recovery.

etcd snapshots are separate from Velero — Velero backs up Kubernetes resources and PVC data, but if the control plane itself dies, you need the etcd snapshot to restore the cluster state from scratch. Snapshots offloaded to B2 ensure they survive even if the node fails.

---

## Details

- **Prometheus**: ServiceMonitors for all platform components, recording rules for common aggregations
- **Grafana dashboards**: node exporter, Flux GitOps, initial homelab overview (later rebuilt)
- **Velero**: daily full-cluster backup schedule, `apps` and `databases` namespace included
- **etcd snapshots**:
  - k3s built-in snapshot schedule: every 6 hours, keep 5 local snapshots
  - Offload script: `scripts/etcd-snapshot-upload.sh` — uploads latest snapshot to B2 via rclone
  - CronJob on `jaime` (control-plane node): runs post-snapshot upload every 6 hours
- **rclone**: configured with B2 credentials from SOPS secret, `homelab-etcd-snapshots` bucket

---

## Outcome

- Prometheus scraping all components ✓
- Grafana dashboards showing initial data ✓
- Velero daily backup running ✓
- etcd snapshots uploading to B2 every 6 hours ✓

---

## Related

- Velero: `platform/backup/velero/`
- etcd snapshot upload: `scripts/etcd-snapshot-upload.sh`
- B2 rclone config: stored in SOPS secret
