# ADR-015 — Velero Backup Strategy with MinIO on TrueNAS and B2 Offsite

**Status:** Accepted
**Date:** 2026-03-24
**Deciders:** Kagiso

---

## Context

The cluster runs stateful workloads with data that cannot be reconstructed from Git:
Nextcloud files, Immich photos, Authentik user accounts, PostgreSQL databases. A cluster
rebuild from Git restores the application configuration — it does not restore user data.

Two categories of state need backup:

1. **Kubernetes object state** — Deployments, ConfigMaps, Secrets, PVCs, HelmReleases.
   Most of this is already in Git (GitOps). What is not: runtime state like Kubernetes
   Secrets that Flux doesn't manage, CRD instances, and namespace-scoped resources.

2. **Volume data** — the actual content of PVCs: database files, uploaded files, photos.
   This is not in Git and cannot be recovered from any source other than a backup.

---

## Decision

**Velero** for Kubernetes object and volume backup, with:

- **MinIO on TrueNAS** (10.0.10.80:9000) as the primary backup target
- **Backblaze B2** as the offsite tier via a nightly `rclone` sync from TrueNAS
- **Two schedules**: daily full-cluster backup at 03:00, 6-hourly `databases` namespace backup

---

## Rationale

### Velero over etcd snapshots only

k3s includes `k3s etcd-snapshot` which produces consistent snapshots of etcd state.
etcd holds all Kubernetes objects but does not hold PVC data — volume contents live on
disk, not in etcd. An etcd restore brings back the object graph but PVCs are re-created
empty.

For a cluster where the valuable state is user data (photos, files, database rows), etcd
snapshots alone are insufficient. Velero backs up both: object state via the Kubernetes API
and volume data via file-system-level backup (kopia, in the restic-compatible mode).

Both are used: etcd snapshots run at 02:00 (before Velero) as a fast cluster-state recovery
path; Velero runs at 03:00 for full data recovery.

### MinIO on TrueNAS as primary target

Velero requires an S3-compatible object store. MinIO running on TrueNAS provides this
without any external service dependency. TrueNAS is already the NFS storage backend —
adding a MinIO instance keeps backup infrastructure co-located with the primary storage
appliance.

Critically, MinIO on TrueNAS is **outside the cluster**. If the cluster is destroyed,
the backup target remains accessible. A backup target inside the cluster (e.g. MinIO
running as a Deployment) would be lost with the cluster.

### Backblaze B2 as offsite tier

TrueNAS MinIO is on-site. A fire, flood, or NAS failure takes both the cluster and the
primary backup. B2 is the 3-2-1 offsite copy: data on B2 survives any single-site failure.

Rather than running Velero with a second `BackupStorageLocation` pointing at B2 (which
doubles Velero's upload work and B2 API calls), a nightly `rclone sync` job on TrueNAS
copies the MinIO bucket contents to B2. This keeps Velero simple (one target) and uses
TrueNAS's local network to sync to B2 — faster than the k3s nodes uploading directly.

### Backup schedules

| Schedule | Target | Cadence | Retention |
|----------|--------|---------|-----------|
| `daily-cluster-backup` | All namespaces except `kube-system`, `flux-system` | 03:00 daily | 7 days |
| `frequent-databases-backup` | `databases` namespace only | 01:00, 07:00, 13:00, 19:00 | 48h (8 backups) |

The `databases` namespace gets 6-hourly backups because PostgreSQL data (Nextcloud, Authentik,
Vaultwarden) is the highest-value, highest-change-rate data. A 24-hour RPO on database
changes is not acceptable; 6 hours is a reasonable homelab compromise.

`kube-system` and `flux-system` are excluded from backups — both are fully reconstructed
from k3s install and Flux bootstrap respectively.

### No volume snapshots

`snapshotVolumes: false` with `defaultVolumesToFsBackup: true` — Velero uses file-system
backup (kopia) rather than CSI volume snapshots. The NFS and local-path provisioners in
use do not support CSI snapshots. File-system backup is the only viable option.

---

## Consequences

- PVC data is backed up daily with 7-day retention; database PVCs are backed up 6-hourly
- Backup target (MinIO on TrueNAS) survives cluster destruction
- Offsite copy (B2) survives site-level failure
- Velero restore is a manual process — there is no automated restore testing. This is a known gap.
- MinIO storage on TrueNAS consumes ZFS pool space — retention settings must be monitored
- The `rclone` B2 sync schedule on TrueNAS is not managed by this repo — it is configured directly on TrueNAS
