
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
├── /mnt/archive/k8s-backups/etcd/     (etcd snapshots)
└── /mnt/archive/k8s-backups/velero/   (Velero backup data)
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
core/  or  archive/  or  tera/
├── k8s-volumes/           dataset (no compression, quota: 500Gi)
├── k8s-backups/
│   ├── etcd/              dataset (compression: lz4, quota: 10Gi)
│   └── velero/            dataset (compression: lz4, quota: 100Gi)
└── media/                 dataset (compression: off, no quota)
```

ZFS periodic snapshot schedule (configure in TrueNAS UI):

| Dataset | Schedule | Retention |
|---------|----------|-----------|
| k8s-volumes | Daily | 7 days |
| k8s-backups/etcd | Hourly | 7 days |
| k8s-backups/velero | Daily | 30 days |

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

- [Guide 08: Cluster Backups](../08-Cluster-Backups.md)
- [Guide 12: Storage Architecture](../12-Storage-Architecture.md)
- [ADR-004: SOPS + age](./decisions/ADR-004-sops-age-secrets.md)
