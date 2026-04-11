# ADR-016 — TrueNAS SCALE as the NFS Storage Backend

**Status:** Accepted
**Date:** 2026-01-15
**Deciders:** Kagiso

---

## Context

The cluster needs persistent storage for stateful workloads. Most applications require
`ReadWriteOnce` block storage for databases and `ReadWriteMany` for shared file access
(Nextcloud, media libraries). The platform must also support Velero backups and have
enough capacity for a media server.

Three approaches were evaluated:

1. **Dedicated NAS appliance** (TrueNAS) — purpose-built storage hardware running ZFS
2. **Storage node in the cluster** — a fourth bare-metal node running Longhorn or Rook/Ceph
3. **Local storage only** — `local-path` on each node, no shared storage

---

## Decision

**TrueNAS SCALE** running on a repurposed desktop (10.0.10.80) with a ZFS pool, providing:

- NFS exports consumed by the `nfs-subdir-external-provisioner` in the cluster
- MinIO for S3-compatible Velero backup storage
- The primary storage target for all stateful workloads except those that require local-path

---

## Rationale

### Dedicated NAS over a storage node in the cluster

A Kubernetes storage node running Longhorn or Rook/Ceph would distribute storage across
the existing nodes or a fourth node. Both have significant operational costs:

**Longhorn** is easier to operate than Ceph but still requires dedicated disks on each
node, has a non-trivial resource footprint (a daemonset on every node), and has known
failure modes with NFS-backed volumes (stale handles — see ADR-006). It also places
storage inside the cluster, meaning a cluster failure can take storage with it.

**Rook/Ceph** provides enterprise-grade distributed storage but requires at minimum three
storage nodes with dedicated OSD disks. The resource and complexity overhead is entirely
disproportionate for a three-node homelab. Ceph is a full-time operational concern.

A dedicated NAS is operationally simpler: it runs independently of the Kubernetes cluster,
survives cluster destruction, and has a purpose-built management interface (TrueNAS) that
handles ZFS pool management, SMART monitoring, and snapshot scheduling without Kubernetes
involvement.

### TrueNAS SCALE over a Linux NFS server

A plain Linux box with NFS exports would work. TrueNAS SCALE adds:

- **ZFS**: copy-on-write, checksumming, snapshots, scrubs, and compression out of the box.
  Data integrity guarantees that a plain ext4 NFS server cannot provide.
- **SMART monitoring**: drive health monitoring with web UI alerts
- **MinIO app**: S3-compatible object store for Velero, installable from the TrueNAS app catalogue
- **Snapshot scheduling**: automatic ZFS snapshots on a cron schedule, no manual setup
- **Web UI**: manageable without SSH for day-to-day tasks

TrueNAS SCALE is Debian-based and supports standard Linux tooling when needed.

### Local-path for databases, NFS for everything else

NFS is unsuitable for database workloads (WAL writes, file locking) — see ADR-006 for the
full failure analysis. The rule is:

- **`nfs-truenas`** for applications that tolerate NFS: Nextcloud data, Immich media,
  Grafana dashboards, Loki logs, Velero backup metadata
- **`nfs-databases`** for PostgreSQL data — a dedicated NFS export with `maproot_user=root`
  and no uid squash, required for container uid 999 to write to the share
- **`local-path`** for Redis (cache, data loss acceptable) and any workload where
  NFS reliability is unacceptable

---

## Hardware

The TrueNAS host is a repurposed desktop that was no longer needed for compute:

| Component | Detail |
|-----------|--------|
| IP | 10.0.10.80 |
| ZFS pool | Mirror (2 drives) |
| Role | NFS server, MinIO host, ZFS snapshot target |

---

## Consequences

- All stateful workloads (except databases and Redis) use NFS-backed PVCs — a TrueNAS
  outage takes down applications that require their PVCs
- The cluster and storage are decoupled — TrueNAS survives a cluster rebuild
- ZFS provides data integrity and snapshot capability independent of Kubernetes
- NFS is a single point of failure for most application PVCs. Mitigation: ZFS pool is
  mirrored (1-drive failure tolerance), Velero backs up all PVC data daily
- TrueNAS is managed outside of GitOps — its configuration is not in this repo
