# ned — Storage Server (TrueNAS)

**Hostname:** `ned`
**IP:** `10.0.10.80`
**OS:** TrueNAS SCALE (Linux-based)
**Hardware:** HP MicroServer Gen8

---

## The Character

<div align=”center”>

<!-- Photo placeholder: Eddard “Ned” Stark (Sean Bean) from Game of Thrones -->
> _📸 Photo coming soon — Ned Stark_

</div>

**Eddard “Ned” Stark** is the Lord of Winterfell and Warden of the North. He is the foundation upon which the entire Stark family rests — honourable, dependable, and immovable. Winterfell stands because Ned holds it. Everything the Starks are and do flows from that foundation.

**Why this machine:** `ned` is the foundation of the homelab. Every persistent volume in the cluster lives on ned's ZFS pool. Every backup — Velero, etcd, varys keys — lands on ned. If ned goes down, data is at risk. Like the character, ned is not glamorous, not in the spotlight, but everything rests on him. The homelab stands because ned holds it.

---

## Role

TrueNAS is the **persistent storage layer** for the entire homelab. It serves two functions:

1. **Network storage** â€” NFS shares provide Kubernetes persistent volumes via the NFS subdir external provisioner
2. **Backup target** â€” MinIO (S3-compatible) receives Velero backups from the k3s cluster; etcd snapshots are written directly to NFS

```
k3s cluster
    â”‚
    â”œâ”€â”€â–º NFS (10.0.10.80:/mnt/core/k8s_volumes)     â† Kubernetes PVCs
    â”‚
    â”œâ”€â”€â–º NFS (10.0.10.80:/mnt/archive/backups/k8s) â† etcd snapshots + host backups
    â”‚
    â””â”€â”€â–º MinIO (10.0.10.80:9000, bucket: velero)     â† Velero backups
                    â”‚
                    â””â”€â”€â–º Backblaze B2 (Cloud Sync, nightly)  â† offsite
```

---

## Hardware

| Component | Detail |
|-----------|--------|
| Model | HP MicroServer Gen8 |
| CPU | Intel E3-1260l v2 (4C/4T) |
| RAM | 16GB ECC DDR3 |
| Boot drive | 128GB SSD 2.5" (TrueNAS OS) |
| Data drives | 2Ã— 480GB SATA SSD in app ZFS pool |
| Data drives | 2Ã— 4TB SAS HDD in archive ZFS pool |
| Data drives | 2Ã— 8TB SAS HDD in media ZFS pool |
| NIC | 1GbE onboard |
| IP | 10.0.10.80 (static IP) |

---

## ZFS Pool

| Pool | Layout | Datasets |
|------|--------|---------|
| `core` | SSD Mirror | `k8s_volumes` |
| `archive` | HDD Mirror | `backups/k8s`, `backups/docker`, `backups/varys` |
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

- [Guide 10 â€” Backups & Disaster Recovery](../docs/guides/10-Backups-Disaster-Recovery.md) â€” etcd snapshots, Velero + MinIO setup
- [Guide 08 â€” Storage Architecture](../docs/guides/08-Storage-Architecture.md) â€” NFS provisioner, StorageClass, PVC lifecycle
