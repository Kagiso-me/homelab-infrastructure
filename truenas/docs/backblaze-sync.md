# TrueNAS — Backblaze B2 Cloud Sync

Backblaze B2 is the **offsite backup layer** (Layer 4) of the backup strategy. TrueNAS Cloud Sync replicates the backup datasets to B2 nightly, providing protection against total TrueNAS hardware failure.

---

## Backup Layer Summary

```
Layer 1 — Git        Kubernetes manifests        Always current (automatic)
Layer 2 — NFS        etcd snapshots on TrueNAS   Daily 02:00, 7-day retention
Layer 3 — MinIO      Velero PVC backups           Daily 03:00, 7-day retention
Layer 4 — B2         TrueNAS → Backblaze B2       Nightly, 30-day retention  ← this doc
```

Layer 4 protects against scenarios that would destroy TrueNAS itself: hardware failure, fire, theft.

---

## Prerequisites

1. A [Backblaze account](https://www.backblaze.com) (free tier: 10 GB; paid: $0.006/GB/month)
2. A B2 bucket created in the Backblaze web UI
3. A B2 application key with write access to that bucket

---

## Step 1 — Create Backblaze B2 Bucket

In the Backblaze web UI:

1. **Buckets → Create a Bucket**
2. Bucket name: `homelab-truenas-backup` *(must be globally unique — prefix with your username)*
3. Files in Bucket: **Private**
4. Default Encryption: Enabled (recommended)
5. Object Lock: Disabled

Note the bucket name — you will need it for the Cloud Sync task.

---

## Step 2 — Create B2 Application Key

In the Backblaze web UI:

1. **Account → Application Keys → Add a New Application Key**
2. Name: `truenas-cloud-sync`
3. Allow access to: **specific bucket** → select your bucket
4. Type of access: **Read and Write**
5. Click **Create New Key**

Copy both values immediately — the `applicationKey` is shown only once:

| Credential | Where to use |
|-----------|-------------|
| `keyID` | TrueNAS Cloud Sync credential |
| `applicationKey` | TrueNAS Cloud Sync credential |

---

## Step 3 — Configure Cloud Sync in TrueNAS

Navigate to: **Data Protection → Cloud Sync Tasks → Add**

### Cloud Credential (create once)

Navigate to: **Credentials → Backup Credentials → Cloud Credentials → Add**

| Setting | Value |
|---------|-------|
| Name | `Backblaze B2` |
| Provider | `Backblaze B2` |
| Key ID | *(paste keyID from Step 2)* |
| Application Key | *(paste applicationKey from Step 2)* |

Click **Verify Credential** — should succeed.

### Cloud Sync Task

| Setting | Value |
|---------|-------|
| Description | `homelab-backup-offsite` |
| Direction | **PUSH** |
| Transfer Mode | **SYNC** |
| Remote Credential | `Backblaze B2` (from above) |
| Bucket | `homelab-truenas-backup` |
| Folder | `/` *(root of bucket)* |
| Directory/Files | `/mnt/archive/backups` |
| Schedule | Daily at 04:00 *(after Velero at 03:00)* |
| Enabled | Yes |

Under **Advanced Options**:

| Setting | Value |
|---------|-------|
| Transfers | 4 |
| Bandwidth Limit | *(optional — set if on metered connection)* |
| Encryption | Enabled (encrypt files server-side on B2) |
| Encryption Password | *(generate strong password — store in password manager)* |

> The encryption password is required to decrypt B2 files if you ever need to restore from B2 directly. Store it alongside your other backup credentials.

---

## Step 4 — Test the Sync

After creating the task, run it manually:

1. In **Data Protection → Cloud Sync Tasks**, click the **Run Now** (▷) button
2. Watch the task log — it should show files being transferred
3. In the Backblaze web UI, verify files appear in the bucket

---

## Retention

B2 does not natively enforce retention periods. Options:

**Option A — Lifecycle rules (recommended)**

In the Backblaze web UI, under **Bucket Settings → Lifecycle Rules**:

| Rule | Value |
|------|-------|
| Keep prior versions for | 30 days |
| Delete files older than | 30 days |

**Option B — Manual pruning**

Use TrueNAS Cloud Sync with **Transfer Mode: SYNC** — this mirrors the source. When TrueNAS prunes old snapshots from `k8s/etcd/`, the next sync removes them from B2 as well. The B2 copy is effectively as fresh as the TrueNAS copy.

---

## Restoring from B2

If TrueNAS is completely lost, restore from B2:

```bash
# Install rclone on your laptop or RPi
curl https://rclone.org/install.sh | sudo bash

# Configure rclone with B2 credentials
rclone config

# List backup contents
rclone ls b2:homelab-truenas-backup/

# Restore etcd snapshot to local disk
rclone copy b2:homelab-truenas-backup/etcd/k3s-snapshot-YYYY-MM-DD_HHmmss.db ./

# See cluster-rebuild runbook for what to do next
```

See [cluster-rebuild runbook](../../docs/operations/runbooks/cluster-rebuild.md) for the full recovery procedure.

---

## Monitoring

TrueNAS displays Cloud Sync task history under **Data Protection → Cloud Sync Tasks**.

For Prometheus/Grafana monitoring, the script `truenas/scripts/b2-sync-metrics.sh` runs on TrueNAS after each sync and writes metrics to the node_exporter textfile collector.

### Deploying b2-sync-metrics.sh

```bash
# From bran — copy script to TrueNAS (root fs is read-only; use a ZFS pool path)
scp ~/homelab-infrastructure/truenas/scripts/b2-sync-metrics.sh kagiso@10.0.10.80:~/b2-sync-metrics.sh
ssh kagiso@10.0.10.80 "sudo mkdir -p /mnt/core/scripts && sudo mv ~/b2-sync-metrics.sh /mnt/core/scripts/b2-sync-metrics.sh && sudo chmod 750 /mnt/core/scripts/b2-sync-metrics.sh"
```

Create `/etc/b2-sync-metrics.conf` (on TrueNAS, chmod 600):

```
TRUENAS_API_KEY=<api-key>
B2_RCLONE_REMOTE=b2remote
B2_BUCKET=homelab-infrastructure
TASK_PATTERN=homelab-backup-offsite
TEXTFILE_DIR=/var/lib/node_exporter/textfile_collector
```

> **Note:** `TASK_PATTERN` must match the Cloud Sync task description exactly. Ours is `homelab-backup-offsite`.
> **Note:** TrueNAS root filesystem is read-only — deploy the script to `/mnt/core/scripts/`, not `/usr/local/bin/`.

Configure rclone for B2 (run once as root on TrueNAS):

```bash
rclone config create b2remote b2 account <keyID> key <appKey>
# rclone saves config to the user's home — copy it to root for sudo access
sudo mkdir -p /root/.config/rclone
sudo cp ~/.config/rclone/rclone.conf /root/.config/rclone/rclone.conf
```

Test run:

```bash
sudo /mnt/core/scripts/b2-sync-metrics.sh
# Expected: B2 metrics written — status=1 size=<bytes> files=<count>
```

Create the cron task in TrueNAS UI:

> **System → Advanced → Cron Jobs → Add**
> - Command: `/mnt/core/scripts/b2-sync-metrics.sh`
> - Run As: `root`
> - Schedule: `0 5 * * *` (05:00 daily — one hour after the 04:00 B2 sync)

Metrics written to `/var/lib/node_exporter/textfile_collector/b2_sync.prom`:

| Metric | Description |
|--------|-------------|
| `backup_job_status{job="truenas-b2-sync"}` | `1` = last sync succeeded, `0` = failed |
| `backup_last_success_timestamp{job="truenas-b2-sync"}` | Unix timestamp of last successful sync |
| `b2_bucket_size_bytes{bucket="homelab-infrastructure"}` | Total bytes in B2 bucket |
| `b2_bucket_file_count{bucket="homelab-infrastructure"}` | File count in B2 bucket |
