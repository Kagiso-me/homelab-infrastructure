# Data Integrity Policy

## Document Control

| Field        | Value             |
|--------------|-------------------|
| Version      | 1.0               |
| Date         | 2026-03-14        |
| Status       | Active            |
| Owner        | Platform Engineer |
| Review Cycle | Quarterly         |

---

## 1. Purpose and Scope

This policy defines the data integrity controls, verification procedures, known limitations, and recommendations for data stored within the homelab Kubernetes infrastructure.

**In scope:**
- Persistent Volume Claim (PVC) data backed by NFS volumes on TrueNAS (StorageClass: `nfs-truenas`)
- Kubernetes cluster state stored in etcd
- Backup data stored in MinIO (Velero) and on TrueNAS ZFS datasets
- Offsite backup data in Backblaze B2

**Out of scope:**
- Ephemeral (emptyDir) volumes; these have no persistence guarantee by design
- Git repository data (integrity managed by GitHub and local Git tooling)
- External services and APIs consumed by workloads

---

## 2. Integrity Guarantees by Layer

### 2.1 Storage Layer — TrueNAS ZFS

ZFS provides the foundational data integrity layer for all persistent data in this environment.

| Integrity Feature       | Description                                                                    |
|-------------------------|--------------------------------------------------------------------------------|
| Block-level checksums   | ZFS computes a checksum (SHA-256 or Fletcher4) for every data block on write   |
| Silent corruption detection | On read, ZFS verifies block checksums. Corrupt blocks are detected and flagged |
| Self-healing (RAID-Z)   | If the ZFS pool uses redundancy (mirrors or RAID-Z), corrupt blocks are automatically repaired from the redundant copy |
| ZFS scrub               | Periodic full pool scrub reads all blocks and verifies checksums proactively   |

ZFS scrubs are scheduled monthly on the TrueNAS pool. Scrub results are monitored via TrueNAS SMART and alert emails. Any detected checksum errors are treated as a high-priority incident requiring investigation.

> **Note:** The specific ZFS pool topology (mirror, RAID-Z1, etc.) is defined in TrueNAS configuration. If a single-disk pool is in use, ZFS can detect corruption but cannot self-heal — this must be restored from a backup. The pool topology should be documented in `docs/architecture/storage.md`.

### 2.2 Backup Layer — Velero (Restic/Kopia)

Velero uses Restic or Kopia for filesystem-level PVC backup.

| Integrity Feature         | Description                                                                |
|---------------------------|----------------------------------------------------------------------------|
| Content-addressed storage | Restic/Kopia store backup data as content-addressed chunks (SHA-256 hash) |
| Deduplication             | Duplicate data blocks are stored once; integrity is verified by content hash |
| Repository checksums      | Backup repository metadata includes checksums for all pack files           |
| Restore verification      | `velero restore` verifies data integrity during the restore process        |

Velero backup success is monitored via Prometheus metrics. A backup that completes but contains data corruption would manifest as a restore failure — this is why quarterly restoration testing is required (see Section 5).

### 2.3 etcd Layer — Cluster State

etcd uses a write-ahead log (WAL) and periodic snapshots. Data integrity is maintained by:
- etcd's internal CRC checksums on WAL entries
- k3s snapshot integrity verified on restore (k3s will reject a corrupt snapshot)
- SOPS encryption for Secrets ensures that encrypted values cannot be silently modified without detection by the age decryption step

### 2.4 Transport Layer

All data in transit is protected by TLS:
- NFS traffic between cluster nodes and TrueNAS is on a trusted VLAN (storage network); NFS v3/v4 without additional encryption is accepted at this trust level
- MinIO (Velero backup target) uses HTTPS/TLS for all S3 API calls
- Backblaze B2 sync uses HTTPS for all transfers

---

## 3. Data Retention

| Data Type               | Retention Period    | Mechanism                              |
|-------------------------|---------------------|----------------------------------------|
| PVC data (live)         | Indefinite (in use) | NFS-backed PV; survives pod restarts   |
| Velero backups          | 30 days             | Velero TTL; auto-pruned by Velero      |
| ZFS hourly snapshots    | 7 days              | TrueNAS periodic snapshot task         |
| ZFS daily snapshots     | 30 days             | TrueNAS periodic snapshot task         |
| etcd snapshots          | ~1.25 days (5 copies at 6h) | k3s built-in snapshot retention |
| Backblaze B2            | 30 days minimum     | B2 bucket lifecycle policy             |

PVC data is retained for as long as the PersistentVolumeClaim exists in Kubernetes. When a PVC is deleted with a `Delete` reclaim policy, the underlying NFS data is removed. Workloads that should retain data beyond PVC lifecycle must use a `Retain` reclaim policy — this must be specified explicitly in the PV definition.

---

## 4. Verification Procedures

### 4.1 ZFS Scrub (Monthly)

TrueNAS is configured to run a pool scrub monthly. After each scrub:
- Review scrub results in TrueNAS UI: Storage → Pool → Scrub
- Verify zero checksum errors and zero data errors
- If errors are detected, investigate immediately and cross-reference with backup integrity

### 4.2 Velero Restore Test (Quarterly)

A full restore test of at least one production namespace is performed quarterly:

1. Select a namespace with PVC-backed workloads.
2. Execute: `velero restore create --from-backup <backup-name> --namespace-mappings <source>:<test-ns>`
3. Verify the application starts successfully in the test namespace.
4. Verify PVC data contents are intact (application-level check).
5. Delete the test namespace after verification.
6. Record results in `docs/compliance/dr-test-log.md`.

### 4.3 ZFS Snapshot File Restore (Quarterly)

1. Identify a test file in a PVC-backed NFS dataset.
2. Browse ZFS snapshots via TrueNAS UI: Storage → Snapshots
3. Restore the test file from a snapshot that is at least 24 hours old.
4. Verify file contents match expected data.
5. Record results in `docs/compliance/dr-test-log.md`.

### 4.4 etcd Snapshot Integrity Check (Quarterly)

1. Copy the most recent etcd snapshot to a test location.
2. Verify the snapshot can be listed: `k3s etcd-snapshot list`
3. Optionally, perform a full restore to a single-node test cluster to validate completeness.
4. Record results in `docs/compliance/dr-test-log.md`.

---

## 5. Known Limitations

The following limitations are documented for transparency. They represent accepted constraints given the homelab context.

### 5.1 NFS POSIX Consistency Limitations

NFS (particularly NFSv3) does not provide full POSIX consistency for concurrent writes from multiple clients. Specifically:
- Close-to-open cache consistency is maintained, but concurrent write operations from multiple pods to the same NFS volume are not safe without application-level locking.
- **Mitigation:** RWX (ReadWriteMany) PVCs are used only for workloads that support concurrent NFS access (e.g., static file stores). Databases and workloads requiring strong write consistency use RWO (ReadWriteOnce) PVCs with a single writer.

### 5.2 No Database-Level Backups

Velero backs up PVC data at the filesystem level. This means:
- Databases (PostgreSQL, MySQL, etc.) whose data files reside on PVCs are backed up as raw filesystem data.
- A filesystem-level backup of a running database may capture data in an inconsistent state (e.g., mid-transaction).
- **This does not produce a corrupt backup** for most databases due to WAL-based recovery, but the recovery point may differ from what the application considers a consistent state.
- **Recommendation:** Databases should use Velero backup hooks (`pre.hooks`) to flush and quiesce before backup (see Section 6).

### 5.3 No Point-in-Time Recovery for PV Data

Velero backups run daily. There is no continuous data protection (CDP) or transaction log shipping for PV-backed databases. Maximum data loss for PV data is up to 24 hours (last Velero backup). ZFS hourly snapshots reduce this to ~1 hour for data that remains on the TrueNAS pool, but these are not integrated with Velero.

### 5.4 etcd Snapshots Do Not Include PVC Data

etcd captures Kubernetes API objects (PersistentVolumeClaims, PersistentVolumes, etc.) but not the data within those volumes. A full cluster restore from etcd alone will restore PVC definitions but not PVC contents — Velero is required for data recovery.

---

## 6. Recommendations

### 6.1 Stateless Applications Preferred

Workloads should be designed to be stateless wherever possible. Stateless applications have no data integrity risk at the Kubernetes layer — data is stored in external services (databases, object storage) that have their own integrity mechanisms.

### 6.2 Database Velero Pre-Backup Hooks

For databases that must run as stateful Kubernetes workloads, Velero backup hooks should be configured to ensure a consistent backup:

```yaml
# Example annotation on database pod
backup.velero.io/backup-volumes: data
pre.hook.backup.velero.io/command: '["/bin/bash", "-c", "psql -U postgres -c CHECKPOINT"]'
pre.hook.backup.velero.io/timeout: 60s
```

This ensures the database flushes dirty pages to disk before Velero snapshots the PVC.

### 6.3 ReadWriteOnce for Databases

Databases must use `accessModes: [ReadWriteOnce]` PVCs to prevent multiple writers, which would cause data corruption.

### 6.4 ZFS Dataset Per Application

Where feasible, each application's PVC data should reside on a dedicated ZFS dataset on TrueNAS. This enables:
- Per-application snapshot granularity
- Independent dataset-level restore without affecting other workloads
- Cleaner data lifecycle management when workloads are decommissioned

---

## 7. Policy Compliance and Review

This policy is reviewed quarterly and after any data loss or integrity incident. Verification test results are recorded in `docs/compliance/dr-test-log.md`.

Any detected data integrity failure (ZFS checksum error, failed Velero restore, corrupt etcd snapshot) must be treated as a P1 incident and investigated immediately.

| Version | Date       | Author            | Summary of Changes     |
|---------|------------|-------------------|------------------------|
| 1.0     | 2026-03-14 | Platform Engineer | Initial document       |
