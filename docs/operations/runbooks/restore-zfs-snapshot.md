
# Runbook — Restore a TrueNAS Dataset from a ZFS Snapshot

**Scenario:** Data on TrueNAS has been accidentally deleted, corrupted, or needs to be rolled back. Restore using an existing ZFS snapshot.

**Severity:** High
**RTO Estimate:** ~10 minutes (single file) / ~20 minutes (dataset rollback) / ~30 minutes (clone to new dataset)
**Impact:** During a full dataset rollback, any NFS-mounted volumes will briefly become unavailable. Kubernetes PVCs backed by the rolled-back dataset will experience a brief I/O pause.

> **Related runbooks:** [restore-etcd](./restore-etcd.md) | [restore-from-b2](./restore-from-b2.md) | [restore-truenas-storage](./restore-truenas-storage.md)

---

## What This Alert Means

ZFS snapshots are point-in-time, read-only copies of a dataset. TrueNAS creates automatic periodic snapshots for `core/k8s-volumes` and `archive` datasets. Snapshots allow recovery without needing a full backup restore.

Three recovery paths are covered here:

| Method | Use When |
|--------|----------|
| **Single file restore** | One file was deleted or corrupted |
| **Dataset rollback** | The entire dataset must return to a prior state |
| **Snapshot clone** | You want to inspect or recover from a snapshot non-destructively |

---

## Quick Reference

| Item | Value |
|------|-------|
| TrueNAS address | 10.0.10.80 |
| ZFS pools | `core` (k8s PVCs), `archive` (backups + personal), `tera` (media — no snapshots) |
| SSH access | `ssh kagiso@10.0.10.80` (or via RPi: `ssh kagiso@10.0.10.10`, then `ssh kagiso@10.0.10.80`) |
| Snapshot naming convention | `<pool>/<dataset>@auto-YYYY-MM-DD_HH-MM` |
| NFS exports | `/mnt/core/k8s-volumes`, `/mnt/archive/k8s-backups`, `/mnt/tera` |

---

## Step 1 — SSH to TrueNAS

```bash
# From the Raspberry Pi:
ssh kagiso@10.0.10.10
ssh kagiso@10.0.10.80
```

All CLI commands below run on TrueNAS (10.0.10.80) unless noted.

---

## Step 2 — List available snapshots

List all snapshots for the relevant dataset:

```bash
zfs list -t snapshot -o name,creation,used -s creation |
```

To filter to a specific dataset (e.g., `core/k8s-volumes` or `archive/k8s-backups`):

```bash
zfs list -t snapshot -o name,creation,used -s creation core/k8s-volumes
```

Expected output:

```
NAME                                      CREATION              USED
core/k8s-volumes@auto-2026-03-15_02-00        Sat Mar 15  2:00 2026  0B
core/k8s-volumes@auto-2026-03-14_14-00        Fri Mar 14 14:00 2026  84K
core/k8s-volumes@auto-2026-03-14_02-00        Fri Mar 14  2:00 2026  1.2M
core/k8s-volumes@auto-2026-03-13_14-00        Thu Mar 13 14:00 2026  3.6M
```

Note the snapshot name you want to restore from, e.g., `core/k8s-volumes@auto-2026-03-14_14-00`.

---

## Method A — Single File Restore

Use this when only one or a few files need to be recovered.

### Step A1 — Locate the file in the snapshot

ZFS snapshots are accessible as a hidden `.zfs/snapshot/` directory inside each dataset's mount point:

```bash
ls /mnt/archive/appdata/.zfs/snapshot/
# Lists all snapshot names for this dataset

ls /mnt/archive/appdata/.zfs/snapshot/auto-2026-03-14_14-00/
# Browse the dataset as it looked at that snapshot
```

### Step A2 — Copy the file back

```bash
cp /mnt/archive/appdata/.zfs/snapshot/auto-2026-03-14_14-00/sonarr/sonarr.db \
   /mnt/archive/appdata/sonarr/sonarr.db
```

Verify the restored file:

```bash
ls -lh /mnt/archive/appdata/sonarr/sonarr.db
```

No service restarts or NFS disruption are required. The file is immediately visible to any NFS client.

---

## Method B — Full Dataset Rollback

Use this to revert an entire dataset to a prior snapshot state. **This is destructive — all changes made after the snapshot are lost.**

### Step B1 — Scale down workloads that use the dataset

To prevent data inconsistency during rollback, pause Kubernetes workloads that mount this dataset as a PVC.

```bash
# From tywin (10.0.10.11) — example for sonarr in the media namespace:
kubectl scale deployment sonarr -n media --replicas=0
kubectl get pods -n media    # confirm sonarr pod has terminated
```

### Step B2 — Unmount any NFS clients (if required)

For a clean rollback, confirm no active NFS sessions are writing to the dataset:

```bash
# On TrueNAS, check active NFS connections:
nfsstat -c 2>/dev/null || showmount -a 10.0.10.80
```

### Step B3 — Roll back the dataset

```bash
# Syntax: zfs rollback [-r] <snapshot>
# -r destroys any snapshots taken AFTER the target snapshot

zfs rollback -r core/k8s-volumes@auto-2026-03-14_14-00
```

Expected output: the command returns silently on success.

Verify the rollback:

```bash
zfs list -t snapshot core/k8s-volumes | head -5
# The snapshots newer than the rollback target should be gone
```

### Step B4 — Scale workloads back up

```bash
kubectl scale deployment sonarr -n media --replicas=1
kubectl get pods -n media --watch
# Wait for the pod to reach Running state
```

---

## Method C — Snapshot Clone (Non-Destructive Inspection)

Use this to access an old snapshot as a fully writable dataset without modifying the original. Useful for forensic inspection or copying individual files at leisure.

### Step C1 — Create a clone from the snapshot

```bash
zfs clone core/k8s-volumes@auto-2026-03-14_14-00 core/k8s-volumes-restore-temp
```

### Step C2 — Browse or copy from the clone

```bash
ls /mnt/archive/appdata-restore-temp/
# Copy specific files as needed
cp /mnt/archive/appdata-restore-temp/sonarr/sonarr.db /mnt/archive/appdata/sonarr/sonarr.db
```

### Step C3 — Destroy the clone when done

```bash
zfs destroy core/k8s-volumes-restore-temp
```

---

## TrueNAS UI Method (Alternative)

If CLI is not available, use the TrueNAS web UI at `http://10.0.10.80`:

1. Navigate to **Storage → Snapshots**.
2. Filter by dataset name using the search box.
3. Click the **...** menu on the target snapshot.
4. Select **Rollback** (for full dataset rollback) or **Clone** (for a non-destructive copy).
5. Confirm the warning dialog.

For single-file restore via UI: navigate to **Storage → Datasets**, click the dataset, then select **Snapshots** in the right panel. Use **Browse** to inspect the snapshot contents.

---

## Verify Recovery

```bash
# Confirm dataset contents look correct (check mtime of key files)
ls -lht /mnt/archive/appdata/sonarr/ | head -5

# Confirm Kubernetes PVCs are bound
kubectl get pvc -A | grep -v Bound

# Confirm the application is running and healthy
kubectl get pods -n media
kubectl logs -n media deployment/sonarr --tail=20

# Check NFS exports are still active
showmount -e 10.0.10.80
```

Expected: PVCs show `Bound`, pods are `Running`, NFS exports include the affected dataset path.

---

## Decision Table

| Situation | Method |
|-----------|--------|
| One or a few files need recovery | Method A — single file from `.zfs/snapshot/` |
| Entire dataset must be rewound | Method B — `zfs rollback -r` |
| Need to inspect old state without risk | Method C — `zfs clone` |
| UI preferred or SSH unavailable | TrueNAS Web UI |
| No useful snapshot exists | See [restore-from-b2](./restore-from-b2.md) |
| TrueNAS hardware has failed | See [restore-truenas-storage](./restore-truenas-storage.md) |
