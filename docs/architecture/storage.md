
# Architecture — Storage

## Storage Design Reference

This document describes the storage architecture: how persistent volumes are provisioned, where data lives, and how storage relates to the backup strategy.

---

## Design Principle

**Nodes are compute. Data lives on TrueNAS.**

No application data lives on cluster node disks. All persistent volumes are backed by TrueNAS NFS. A node can be wiped without data loss.

---

## Storage Topology

```
Kubernetes Cluster
│
├── local-path-provisioner   (k3s built-in)
│     └── /var/lib/rancher/k3s/storage/   (node-local, ephemeral use only)
│
└── NFS Subdir Provisioner   (nfs-truenas StorageClass)
      │
      ▼
TrueNAS (10.0.10.80)
│
├── /mnt/core/k8s-volumes/   (PVC backing directories)
├── /mnt/archive/backups/k8s/etcd/     (etcd snapshots)
└── /mnt/archive/backups/k8s/velero/   (Velero backup data)
```

---

## StorageClasses

| Name | Provisioner | Reclaim | Binding | Use case |
|------|------------|---------|---------|---------|
| `nfs-truenas` | nfs-subdir-external-provisioner | Retain | Immediate | All stateful applications |
| `local-path` | rancher.io/local-path | Delete | WaitForFirstConsumer | Ephemeral / non-critical workloads |

`nfs-truenas` is the **default StorageClass** for all production workloads.

---

## PVC Directory Naming on TrueNAS

The NFS provisioner creates directories using this pattern:

```
/mnt/core/k8s-volumes/${namespace}-${pvc-name}-${pv-name}/
```

Example:

```
/mnt/core/k8s-volumes/monitoring-prometheus-data-pvc-abc123/
/mnt/core/k8s-volumes/monitoring-grafana-data-pvc-def456/
/mnt/core/k8s-volumes/apps-jellyfin-config-pvc-ghi789/
```

This naming makes it straightforward to identify which PVC corresponds to which directory on TrueNAS.

---

## Volume Lifecycle

```
PVC created (namespace/name defined)
  │
  ▼
NFS provisioner creates directory on TrueNAS
  │
  ▼
PV created and bound to PVC
  │
  ▼
Pod mounts PVC (ReadWriteOnce)
  │
  ▼
PVC deleted (by operator or Helm uninstall)
  │
  ▼
[archiveOnDelete=true] directory moved to archived/ prefix
  (data NOT destroyed; operator must manually clean up)
```

---

## Access Modes

| Mode | Meaning | Used by |
|------|---------|---------|
| `ReadWriteOnce` (RWO) | Single node read/write | Most stateful apps |
| `ReadWriteMany` (RWX) | Multiple nodes read/write | Media libraries, shared config |
| `ReadOnlyMany` (ROX) | Multiple nodes read-only | Static datasets |

NFS supports all three modes. Most applications use RWO. Media applications (Jellyfin) that need their library accessible from multiple replicas should use RWX.

---

## TrueNAS ZFS Layout

Recommended dataset structure on TrueNAS:

```
core/
└── k8s-volumes/           dataset (compression: lz4)
archive/
└── backups/
    └── k8s/
        ├── etcd/          dataset (compression: lz4)
        └── minio/         dataset (compression: off, sync: disabled)
tera/
└── media/                 dataset (compression: off)
```

ZFS periodic snapshot schedule (configure in TrueNAS UI):

| Dataset | Schedule | Retention |
|---------|----------|-----------|
| k8s-volumes | Daily | 7 days |
| archive (recursive) | Daily | 30 days |

---

## Capacity Planning

Starting recommendations:

| PVC | Size | StorageClass |
|-----|------|-------------|
| prometheus-data | 20Gi | nfs-truenas |
| grafana-data | 2Gi | nfs-truenas |
| loki-data | 20Gi | nfs-truenas |
| alertmanager-data | 1Gi | nfs-truenas |
| jellyfin-config | 2Gi | nfs-truenas |
| sonarr-config | 1Gi | nfs-truenas |
| radarr-config | 1Gi | nfs-truenas |

Monitor actual usage in Grafana. Alert when any PVC exceeds 80% of declared size.

---

## Related Guides

- [Guide 10: Backups & Disaster Recovery](../guides/10-Backups-Disaster-Recovery.md)
- [Guide 08: Storage Architecture](../guides/08-Storage-Architecture.md)
- [ADR-004: SOPS + age](../adr/ADR-004-sops-age-secrets.md)
