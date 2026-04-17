# 2026-04 — DEPLOY: Add nfs-databases StorageClass for database workloads

**Operator:** Kagiso
**Type:** `DEPLOY`
**Components:** TrueNAS · NFS · StorageClass · PostgreSQL · Redis
**Commit:** —
**Downtime:** None

---

## What Changed

Added a dedicated `nfs-databases` StorageClass pointing at a separate TrueNAS dataset (`tank/k8s/databases`) distinct from the general `nfs-truenas` class used by other workloads.

---

## Why

All NFS-backed PVs were using a single StorageClass backed by one dataset. Database PVs (PostgreSQL, Redis) competing for I/O with application PVs (Nextcloud files, Immich assets) on the same dataset caused latency spikes under load. A dedicated dataset lets TrueNAS apply separate QoS settings and makes I/O isolation visible in the TrueNAS metrics.

Also enables per-dataset snapshot schedules — databases can snapshot every hour, bulk storage every 6 hours, without one schedule forcing unnecessary snapshots on the other.

---

## Details

- **TrueNAS dataset**: `tank/k8s/databases` — separate ZFS dataset with sync=always and compression=lz4
- **NFS export**: `/mnt/tank/k8s/databases` exported to cluster CIDR only
- **StorageClass**: `nfs-databases`, provisioner `nfs.csi.k8s.io`, reclaimPolicy `Retain`
- **Migrated PVCs**: PostgreSQL primary, Redis
- **Snapshot schedule**: hourly on `tank/k8s/databases`, 24h retention

---

## Outcome

- Database PVCs on dedicated dataset ✓
- No I/O contention with application storage ✓
- Hourly dataset snapshots running ✓

---

## Related

- StorageClass: `platform/storage/storageclass-nfs-databases.yaml`
- TrueNAS dataset config: manual, not GitOps-managed
