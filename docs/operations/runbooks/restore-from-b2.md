
# Runbook — Restore Data from Backblaze B2

**Scenario:** TrueNAS hardware has failed (or local snapshots are unusable) and data must be retrieved from the offsite Backblaze B2 backup.

**Severity:** Critical
**RTO Estimate:** ~60–120 minutes depending on data volume and B2 download speed
**Impact:** Cluster PVCs backed by TrueNAS NFS are unavailable until TrueNAS is restored. Kubernetes workloads that depend on NFS storage will be down.

> **Related runbooks:** [restore-truenas-storage](./restore-truenas-storage.md) | [restore-zfs-snapshot](./restore-zfs-snapshot.md) | [cluster-rebuild](./cluster-rebuild.md)

---

## What This Alert Means

TrueNAS replicates pool data to Backblaze B2 as the last line of defense against local hardware failure. This runbook covers downloading that data from B2 using rclone on the Raspberry Pi (10.0.10.10), which serves as the recovery workstation when TrueNAS is unavailable.

B2 is a cold restore path — use it only when:
- Local ZFS snapshots are inaccessible (TrueNAS hardware dead)
- The data pools are unrecoverable via `zpool import`
- The replacement TrueNAS instance is ready to receive data

**Prerequisites before starting:**
- Replacement TrueNAS instance is online (see [restore-truenas-storage](./restore-truenas-storage.md))
- rclone is installed on the Raspberry Pi (`rclone version`)
- B2 Application Key ID and Application Key are available from password manager / offline backup
- B2 bucket name: confirm in Backblaze console (default: named after hostname, e.g., `homelab-truenas`)

---

## Quick Reference

| Item | Value |
|------|-------|
| Recovery workstation | Raspberry Pi — 10.0.10.10 |
| B2 bucket | `homelab-truenas` (verify in B2 console) |
| rclone remote name | `b2` (configured per steps below) |
| TrueNAS replacement target | 10.0.10.80 |
| Local staging directory | `/mnt/restore-staging/` on RPi or TrueNAS |

---

## Step 1 — SSH to the Raspberry Pi

```bash
ssh kagiso@10.0.10.10
```

All commands below run on the RPi unless otherwise specified.

---

## Step 2 — Confirm rclone is installed

```bash
rclone version
```

If rclone is missing:

```bash
sudo apt-get update && sudo apt-get install -y rclone
```

---

## Step 3 — Configure rclone for Backblaze B2

If a working rclone config already exists, skip to Step 4.

```bash
rclone config show | grep -A5 "\[b2\]"
```

If the `[b2]` remote is missing, create it non-interactively. Retrieve the key values from the password manager before running:

```bash
rclone config create b2 b2 \
  account "YOUR_B2_KEY_ID" \
  key "YOUR_B2_APPLICATION_KEY"
```

Verify the connection:

```bash
rclone lsd b2:
# Expected: lists your B2 buckets, including homelab-truenas
```

---

## Step 4 — Inspect available data in B2

List the top-level contents of the backup bucket:

```bash
rclone ls b2:homelab-truenas/ --max-depth 1
```

List a specific dataset path (e.g., etcd backups):

```bash
rclone ls b2:homelab-truenas/k8s-backups/etcd/ | sort | tail -10
```

Check the total size of the data to be downloaded:

```bash
rclone size b2:homelab-truenas/
```

This gives a download time estimate. At typical home upload/download speeds (~100 Mbps), 100 GB takes roughly 90 minutes.

---

## Step 5 — Choose what to restore

Determine the minimum data set needed based on the failure scenario.

| Priority | Dataset Path in B2 | Kubernetes Impact |
|----------|--------------------|-------------------|
| 1 — Critical | `k8s-backups/etcd/` | Cluster state (restore first) |
| 2 — High | `k8s-backups/velero/` | PVC application data |
| 3 — High | `appdata/` | Application config and databases |
| 4 — Medium | `media/` | Media library (large, restore last) |

---

## Step 6 — Download data from B2 to TrueNAS

If the replacement TrueNAS is online and its NFS share is mountable, restore directly to TrueNAS:

```bash
# Mount the TrueNAS NFS share on the RPi as a staging area
sudo mkdir -p /mnt/restore-staging
sudo mount 10.0.10.80:/mnt/archive /mnt/restore-staging

# Sync from B2 to TrueNAS — start with etcd backups (smallest, highest priority)
rclone sync b2:homelab-truenas/k8s-backups/etcd/ \
  /mnt/restore-staging/k8s-backups/etcd/ \
  --progress \
  --transfers 4 \
  --checkers 8
```

Restore Velero MinIO data:

```bash
rclone sync b2:homelab-truenas/k8s-backups/velero/ \
  /mnt/restore-staging/k8s-backups/velero/ \
  --progress \
  --transfers 4 \
  --checkers 8
```

Restore application data:

```bash
rclone sync b2:homelab-truenas/appdata/ \
  /mnt/restore-staging/appdata/ \
  --progress \
  --transfers 4 \
  --checkers 8
```

Restore media library (large — run in background or in a `screen` session):

```bash
screen -S b2-restore
rclone sync b2:homelab-truenas/media/ \
  /mnt/restore-staging/media/ \
  --progress \
  --transfers 8 \
  --checkers 16
# Detach: Ctrl+A, D
# Reattach later: screen -r b2-restore
```

---

## Step 7 — Verify downloaded data integrity

rclone's `check` command compares local files against B2 using checksums:

```bash
rclone check b2:homelab-truenas/k8s-backups/etcd/ \
  /mnt/restore-staging/k8s-backups/etcd/ \
  --one-way
```

Expected output: `Checks: N, Transferred: 0, Errors: 0`

Any errors mean files did not download correctly — re-run the `rclone sync` for the affected path.

---

## Step 8 — Restore etcd from the downloaded snapshot

Once `k8s-backups/etcd/` is on the restored TrueNAS NFS share, follow the full etcd restore procedure:

See [restore-etcd](./restore-etcd.md).

The snapshot will be available at `/mnt/backups/etcd/` on tywin once the NFS mount is re-established.

---

## Step 9 — Restore Velero PVC data

Once Velero is running (bootstrapped via Flux), point it at the restored MinIO data and run:

```bash
# Confirm Velero can see its BackupStorageLocation
velero backup-location get
# Expected: STATUS = Available

# List restored backups
velero backup get

# Restore the most recent full backup
velero restore create --from-backup <backup-name> --wait
velero restore describe <restore-name>
```

---

## Verify Recovery

```bash
# Confirm data is present on TrueNAS NFS
ls -lht /mnt/restore-staging/k8s-backups/etcd/ | head -5
ls -lht /mnt/restore-staging/appdata/ | head -5

# Confirm rclone check passes
rclone check b2:homelab-truenas/k8s-backups/ \
  /mnt/restore-staging/k8s-backups/ --one-way

# After k3s is restored — verify cluster is healthy
kubectl get nodes
kubectl get pods -A | grep -Ev 'Running|Completed|Succeeded'
flux get kustomizations

# Verify Velero sees its storage
velero backup-location get
velero backup get
```

---

## Decision Table

| Situation | Action |
|-----------|--------|
| rclone remote not configured | Run Step 3 to configure `b2` remote |
| rclone lsd b2: returns no buckets | Verify B2 key permissions in Backblaze console |
| NFS mount to TrueNAS fails | TrueNAS not ready — see [restore-truenas-storage](./restore-truenas-storage.md) |
| B2 download speed is very slow | Reduce `--transfers` to 2; check RPi network link |
| File checksum errors on rclone check | Re-run `rclone sync` for the affected path |
| etcd snapshot downloaded but corrupted | Try the next-oldest snapshot from `rclone ls b2:` |
| Media library too large to fully download | Restore `appdata/` and `k8s-backups/` first; media can be rebuilt from source |
