# TrueNAS — Storage Server

**Hostname:** `truenas`
**IP:** `10.0.10.80`
**OS:** TrueNAS SCALE (Linux-based)
**Hardware:** HP MicroServer Gen8

---

## Role

TrueNAS is the **persistent storage layer** for the entire homelab. It serves two functions:

1. **Network storage** — NFS shares provide Kubernetes persistent volumes via the NFS subdir external provisioner
2. **Backup target** — MinIO (S3-compatible) receives Velero backups from the k3s cluster; etcd snapshots are written directly to NFS

```
k3s cluster
    │
    ├──► NFS (10.0.10.80:/mnt/core/k8s-volumes)     ← Kubernetes PVCs
    │
    ├──► NFS (10.0.10.80:/mnt/archive/backups/k8s) ← etcd snapshots + host backups
    │
    └──► MinIO (10.0.10.80:9000, bucket: velero)     ← Velero backups
                    │
                    └──► Backblaze B2 (Cloud Sync, nightly)  ← offsite
```

---

## Hardware

| Component | Detail |
|-----------|--------|
| Model | HP MicroServer Gen8 |
| CPU | Intel E3-1260l v2 (4C/4T) |
| RAM | 16GB ECC DDR3 |
| Boot drive | 128GB SSD 2.5" (TrueNAS OS) |
| Data drives | 2× 480GB SATA SSD in app ZFS pool |
| Data drives | 2× 4TB SAS HDD in archive ZFS pool |
| Data drives | 2× 8TB SAS HDD in media ZFS pool |
| NIC | 1GbE onboard |
| IP | 10.0.10.80 (static IP) |

---

## ZFS Pool

| Pool | Layout | Datasets |
|------|--------|---------|
| `core` | SSD Mirror | `k8s-volumes` |
| `archive` | HDD Mirror | `backups/k8s`, `backups/docker`, `backups/rpi` |
| `tera` | Single HDD | `media`, `downloads` |

See [docs/dataset-layout.md](docs/dataset-layout.md) for the full ZFS dataset structure.

---

## Services

| Service | Endpoint | Purpose |
|---------|---------|---------|
| NFS server | 10.0.10.80 (ports 111, 2049) | Kubernetes persistent volumes |
| MinIO | http://10.0.10.80:9000 (API), :9001 (Console) | Velero S3 backup target |
| TrueNAS Web UI | http://10.0.10.80 | Administration |
| SSH | 10.0.10.80:22 | Emergency access |

---

## Documentation

| Document | Description |
|----------|-------------|
| [docs/dataset-layout.md](docs/dataset-layout.md) | ZFS pool and dataset structure |
| [docs/nfs-configuration.md](docs/nfs-configuration.md) | NFS share settings for Kubernetes |
| [docs/minio-configuration.md](docs/minio-configuration.md) | MinIO app setup and bucket layout |
| [docs/backblaze-sync.md](docs/backblaze-sync.md) | Offsite Cloud Sync to Backblaze B2 |

---

## Relationship to Kubernetes Guides

The Kubernetes guides that reference TrueNAS:

- [Guide 10 — Backups & Disaster Recovery](../docs/guides/10-Backups-Disaster-Recovery.md) — etcd snapshots, Velero + MinIO setup
- [Guide 08 — Storage Architecture](../docs/guides/08-Storage-Architecture.md) — NFS provisioner, StorageClass, PVC lifecycle
