# TrueNAS — ZFS Dataset Layout

TrueNAS runs three separate ZFS pools, each with a distinct purpose, redundancy level, and backup
policy. There is no single "tank" pool — all documentation and configuration must reference the
correct pool by name.

---

## Pool Summary

| Pool | Vdevs | Redundancy | Size | Purpose | Backed Up |
|------|-------|-----------|------|---------|-----------|
| `core` | 2× 480GB 2.5" SSD | Mirror | ~480GB usable | Kubernetes PVCs (NFS) | Yes — daily snapshot + B2 |
| `archive` | 2× 4TB SAS HDD | Mirror | ~4TB usable | All backups + personal data | Yes — daily snapshot + B2 |
| `tera` | 1× 8TB SAS HDD | None (single) | ~8TB usable | Media (movies/series/music) | **No** — replaceable content |

> **OS boot drive:** Separate 128GB 2.5" SSD (not part of any ZFS pool).

---

## Dataset Trees

### `core` — Kubernetes Persistent Volumes

```
core/
└── k8s-volumes/           # Kubernetes PVCs via NFS subdir provisioner
    └── (subdirectories created automatically by NFS provisioner)
        # Naming pattern: <namespace>-<pvcname>-<pvname>/
        # e.g. monitoring-grafana-pvc-<uid>/
        #      monitoring-prometheus-data-pvc-<uid>/
        #      media-jellyfin-config-pvc-<uid>/
```

NFS export path: `/mnt/core/k8s-volumes`
NFS server: `10.0.10.80`

### `archive` — Backups

```
archive/
└── backups/               # All backup destinations
    └── k8s/               # Kubernetes cluster backups
        ├── etcd/          # k3s etcd snapshots (written by k3s every 6 hours)
        │   └── k3s-snapshot-YYYY-MM-DD_HHmmss.db
        └── minio/         # MinIO application data
            └── velero/    # Velero backup bucket
                └── (backup objects)
```

NFS export path: `/mnt/archive/backups`
NFS server: `10.0.10.80`

### `tera` — Media Storage

```
tera/
├── downloads/             # In-progress downloads (staging area)
└── media/                 # Movies and TV series
```

NFS export path: `/mnt/tera/media`
NFS server: `10.0.10.80`

> **No backup policy for `tera`.** This pool contains media that can be re-downloaded.
> Running on a single disk — a disk failure results in total data loss. SMART monitoring is critical.

---

## Dataset Settings

| Dataset | Compression | Sync | Record Size | Rationale |
|---------|------------|------|-------------|-----------|
| `core/k8s-volumes` | lz4 | Standard | 128K | NFS PVCs — general workloads |
| `archive/backups` | lz4 | Standard | 128K | Backup parent |
| `archive/backups/k8s` | lz4 | Standard | 128K | k8s backup staging |
| `archive/backups/k8s/minio` | off | Disabled | 1M | MinIO manages its own consistency |
| `tera/downloads` | lz4 | Standard | 128K | Staging only |
| `tera/media` | off | Standard | 1M | Pre-compressed video; large sequential reads |

> MinIO sync is disabled deliberately — MinIO has its own internal consistency mechanisms and
> TrueNAS sync adds latency without benefit.

---

## ZFS Snapshot Schedule

Configured in TrueNAS UI under **Data Protection → Periodic Snapshot Tasks**:

| Dataset | Schedule | Retention | Purpose |
|---------|---------|-----------|---------|
| `core/k8s-volumes` | Daily 01:00 | 7 days | Point-in-time recovery for PVC data |
| `archive` (recursive) | Daily 01:30 | 30 days | Snapshot all backup data |

`tera` is **not** included in the snapshot schedule — media is not backed up.

---

## ZFS Scrub Schedule

Configure in TrueNAS UI under **Data Protection → Scrub Tasks**:

| Pool | Schedule | Threshold |
|------|---------|-----------|
| `core` | Monthly (first Sunday) | 35 days |
| `archive` | Monthly (first Sunday) | 35 days |
| `tera` | Monthly (second Sunday) | 35 days |

Scrubs detect silent data corruption (bit rot). For `tera` (single disk, no redundancy), scrub
errors cannot be auto-repaired — they indicate imminent drive failure requiring immediate action.

---

## Backblaze B2 Cloud Sync

TrueNAS Cloud Sync task runs nightly and syncs to Backblaze B2:

- **Included:** `core/k8s-volumes`, `archive` (all subdatasets)
- **Excluded:** `tera` — too large and not critical
- **Credentials:** stored in TrueNAS keychain (see [`backblaze-sync.md`](backblaze-sync.md))

---

## Creating the Datasets

Run once via TrueNAS UI or SSH after pool creation:

```bash
# core — k8s PVCs (SSD mirror)
zfs create -o compression=lz4 core/k8s-volumes

# archive — backups (HDD mirror)
zfs create -o compression=lz4 archive/backups
zfs create -o compression=lz4 archive/backups/k8s
zfs create -o compression=lz4 archive/backups/k8s/etcd
zfs create -o compression=off -o sync=disabled -o recordsize=1M archive/backups/k8s/minio

# tera — media (single HDD)
zfs create -o compression=lz4 tera/downloads
zfs create -o compression=off -o recordsize=1M tera/media
```

---

## Storage Usage Monitoring

```bash
# Check all pool status and health
zpool status

# Space usage across all pools
zpool list

# Dataset breakdown per pool
zfs list -r core
zfs list -r archive
zfs list -r tera
```

In TrueNAS UI: **Storage → Pools** — usage is shown per pool and dataset.

Prometheus alerts (via node-exporter) monitor `/mnt/core`, `/mnt/archive`, and `/mnt/tera`
mountpoints for space warnings at 80% and critical at 90%.
