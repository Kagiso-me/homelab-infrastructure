# Backup Alert Runbooks

| Field | Value |
|-------|-------|
| File | backup-runbooks.md |
| Covers | EtcdBackupMissing, EtcdBackupTooOld, EtcdBackupSizeSuspicious, DockerBackupMissing, DockerBackupTooOld, DockerBackupSizeSuspicious, RpiBackupMissing, RpiBackupTooOld, VeleroBackupFailed, VeleroBackupTooOld, VeleroBackupStorageUnavailable |
| Last Updated | 2026-03-15 |

---

## Table of Contents

1. [EtcdBackupMissing](#etcdbackupmissing)
2. [EtcdBackupTooOld](#etcdbackuptooold)
3. [EtcdBackupSizeSuspicious](#etcdbackupsizesuspicious)
4. [DockerBackupMissing](#dockerbackupmissing)
5. [DockerBackupTooOld](#dockerbackuptooold)
6. [DockerBackupSizeSuspicious](#dockerbackupsizesuspicious)
7. [RpiBackupMissing](#rpibackupmissing)
8. [RpiBackupTooOld](#rpibackuptooold)
9. [VeleroBackupFailed](#velerobackupfailed)
10. [VeleroBackupTooOld](#velerobackuptooold)
11. [VeleroBackupStorageUnavailable](#velerobackupstorageunavailable)

---

## EtcdBackupMissing

| Field | Value |
|-------|-------|
| Severity | Critical |
| Threshold | `etcd_backup_last_success_timestamp == 0` or metric absent |
| First Response | 15 minutes |

### What This Alert Means

The etcd backup script on `tywin` (10.0.10.11) has never reported a successful backup, or the textfile metric it writes to `/var/lib/node_exporter/textfile_collector/` is absent entirely. Without etcd backups, a control plane failure means full cluster loss.

### Diagnostic Steps

1. SSH to the control plane node:
   ```bash
   ssh kagiso@10.0.10.11
   ```

2. Check whether the textfile metric exists and its content:
   ```bash
   cat /var/lib/node_exporter/textfile_collector/etcd_backup.prom
   ```

3. Check if the backup script exists and is executable:
   ```bash
   ls -la /usr/local/bin/etcd-backup.sh
   ```

4. Check the systemd service or cron job that runs the backup:
   ```bash
   systemctl status etcd-backup.service 2>/dev/null || \
   systemctl status etcd-backup.timer 2>/dev/null || \
   crontab -l | grep -i etcd
   ```

5. Check recent backup job logs:
   ```bash
   journalctl -u etcd-backup.service --since "24 hours ago" --no-pager
   ```

6. Verify the etcd backup destination directory exists and is writable:
   ```bash
   ls -lah /var/lib/rancher/k3s/server/db/snapshots/ 2>/dev/null || \
   ls -lah /backup/etcd/ 2>/dev/null
   ```

7. Run the backup script manually to test:
   ```bash
   sudo /usr/local/bin/etcd-backup.sh
   echo "Exit code: $?"
   ```

8. After manual run, verify the metric was updated:
   ```bash
   cat /var/lib/node_exporter/textfile_collector/etcd_backup.prom
   ```

### Decision Table

| Condition | Action |
|-----------|--------|
| Metric file missing entirely | Script never ran; check cron/timer setup |
| Script not found | Redeploy backup script from GitOps repo |
| Script exists but timer not enabled | `systemctl enable --now etcd-backup.timer` |
| Script runs but fails | Review script logs; check k3s etcd health |
| k3s etcd unhealthy | See [cluster-rebuild.md](../cluster-rebuild.md) |

### Verify Recovery

```bash
# On tywin (10.0.10.11):
cat /var/lib/node_exporter/textfile_collector/etcd_backup.prom
# Expect: etcd_backup_last_success_timestamp > 0

# Confirm backup file written recently:
ls -lah /var/lib/rancher/k3s/server/db/snapshots/ | tail -5
```

---

## EtcdBackupTooOld

| Field | Value |
|-------|-------|
| Severity | Warning |
| Threshold | `time() - etcd_backup_last_success_timestamp > 86400` (>24 hours) |
| First Response | 1 hour |

### What This Alert Means

The etcd backup on `tywin` (10.0.10.11) completed at least once (metric exists with a non-zero value) but has not succeeded in over 24 hours. The backup job is silently failing or being skipped.

### Diagnostic Steps

1. SSH to tywin and check the timestamp:
   ```bash
   ssh kagiso@10.0.10.11
   cat /var/lib/node_exporter/textfile_collector/etcd_backup.prom
   # Note the timestamp value, compare to: date +%s
   ```

2. Check when the last backup file was actually written:
   ```bash
   ls -lah /var/lib/rancher/k3s/server/db/snapshots/
   ```

3. Check the timer or cron schedule:
   ```bash
   systemctl list-timers | grep etcd
   systemctl status etcd-backup.timer
   ```

4. Review logs since the last known good backup:
   ```bash
   journalctl -u etcd-backup.service --since "25 hours ago" --no-pager
   ```

5. Check disk space on tywin (a full disk will silently fail writes):
   ```bash
   df -h /var/lib/rancher/k3s/server/db/snapshots/
   df -h /var/lib/node_exporter/textfile_collector/
   ```

6. Run backup manually and watch output:
   ```bash
   sudo /usr/local/bin/etcd-backup.sh 2>&1
   ```

### Decision Table

| Condition | Action |
|-----------|--------|
| Timer shows "n/a" for last trigger | Timer not active; `systemctl start etcd-backup.timer` |
| Disk full on snapshot path | Clear old snapshots, then run manually |
| Script fails with permission error | Check script runs as root or has sudo |
| Backup succeeds now but was failing | Identify root cause; add alerting on script stderr |

### Verify Recovery

```bash
ssh kagiso@10.0.10.11
cat /var/lib/node_exporter/textfile_collector/etcd_backup.prom
# timestamp should be within last hour if just ran manually
```

---

## EtcdBackupSizeSuspicious

| Field | Value |
|-------|-------|
| Severity | Warning |
| Threshold | `etcd_backup_size_bytes < 1048576` (< 1 MB) or drops >50% from previous |
| First Response | 2 hours |

### What This Alert Means

The etcd backup completed but the resulting file is unusually small. This may indicate a corrupt, empty, or truncated snapshot that would be useless for recovery.

### Diagnostic Steps

1. Check the actual backup file sizes on tywin:
   ```bash
   ssh kagiso@10.0.10.11
   ls -lah /var/lib/rancher/k3s/server/db/snapshots/
   ```

2. Check the size metric in the textfile:
   ```bash
   cat /var/lib/node_exporter/textfile_collector/etcd_backup.prom
   ```

3. Try to validate the snapshot is a valid SQLite/etcd DB (k3s uses SQLite or etcd):
   ```bash
   # For k3s with embedded SQLite:
   file /var/lib/rancher/k3s/server/db/snapshots/<latest-file>

   # For k3s with embedded etcd:
   sudo k3s etcd-snapshot ls
   ```

4. Compare against historical sizes (check NAS copy if offloaded):
   ```bash
   # If backups are synced to TrueNAS:
   ssh admin@10.0.10.80 "ls -lah /mnt/archive/etcd/ | tail -10"
   ```

5. Check if the backup script has an error path that writes an empty file:
   ```bash
   grep -n "touch\|echo.*>" /usr/local/bin/etcd-backup.sh
   ```

### Decision Table

| Condition | Action |
|-----------|--------|
| File is 0 bytes | Script errored after creating file; review logs |
| File is valid but small (<1MB) | Cluster may have very little data; confirm by checking k3s resource count |
| File corrupted | Delete and re-run backup; do not delete previous good copy first |
| All recent backups are small | Investigate k3s etcd state: `sudo k3s etcd-snapshot ls` |

### Verify Recovery

```bash
ssh kagiso@10.0.10.11
sudo k3s etcd-snapshot ls
# Confirm snapshot size is consistent with previous known-good backups
```

---

## DockerBackupMissing

| Field | Value |
|-------|-------|
| Severity | Critical |
| Threshold | `absent(backup_last_success_timestamp{job="docker-appdata"})` for 15 minutes |
| First Response | 15 minutes |

### What This Alert Means

The Docker media server backup script on `10.0.10.20` has never reported a successful backup or the textfile metric is missing entirely from node_exporter's textfile collector.

### Diagnostic Steps

1. SSH to the Docker host via the RPi control hub:
   ```bash
   ssh kagiso@10.0.10.20
   ```

2. Check the textfile metric:
   ```bash
   cat /var/lib/node_exporter/textfile_collector/docker_backup.prom
   ```

3. Verify the backup script is installed:
   ```bash
   ls -la /srv/docker/scripts/backup_docker.sh
   ```

4. Check the cron schedule:
   ```bash
   sudo crontab -l | grep -i backup
   ```

5. Check recent logs:
   ```bash
   tail -50 /var/log/docker-backup.log
   ```

6. Verify backup destination is reachable (backups likely go to TrueNAS via NFS):
   ```bash
   df -h /mnt/archive
   ls -lah /mnt/archive/backups/docker/ 2>/dev/null
   ```

7. Run backup manually:
   ```bash
   sudo /srv/docker/scripts/backup_docker.sh 2>&1
   ```

### Decision Table

| Condition | Action |
|-----------|--------|
| Metric file absent | Script never ran; check cron and the textfile collector path |
| NFS mount /mnt/archive missing | See [DockerNFSMountMissing](infrastructure-runbooks.md#dockernfsmountmissing) |
| Script runs, backup destination full | See [TrueNASDiskFull](infrastructure-runbooks.md#truenasdiskfull) |
| Script errors on Docker commands | Verify Docker daemon is running: `systemctl status docker` |

### Verify Recovery

```bash
ssh kagiso@10.0.10.20
cat /var/lib/node_exporter/textfile_collector/docker_backup.prom
ls -lah /mnt/archive/backups/docker/ | tail -5
```

---

## DockerBackupTooOld

| Field | Value |
|-------|-------|
| Severity | Warning |
| Threshold | `time() - backup_last_success_timestamp{job="docker-appdata"} > 86400` (>24 hours) |
| First Response | 1 hour |

### What This Alert Means

The Docker host backup has not completed successfully in over 24 hours. The backup job is running but failing, or has stopped running entirely.

### Diagnostic Steps

1. SSH to Docker host and check timestamp:
   ```bash
   ssh kagiso@10.0.10.20
   cat /var/lib/node_exporter/textfile_collector/docker_backup.prom
   date +%s  # compare to timestamp in file
   ```

2. Check disk space on backup destination:
   ```bash
   df -h /mnt/archive
   ```

3. Check Docker daemon health:
   ```bash
   docker ps -a --format "table {{.Names}}\t{{.Status}}"
   ```

4. Review backup logs:
   ```bash
   tail -100 /var/log/docker-backup.log
   ```

5. Check if any containers are stuck in a state that blocks backup:
   ```bash
   docker ps -a | grep -v "Up"
   ```

6. Run backup manually:
   ```bash
   sudo /srv/docker/scripts/backup_docker.sh 2>&1 | tee /tmp/backup-test.log
   echo "Exit: $?"
   ```

### Decision Table

| Condition | Action |
|-----------|--------|
| NFS mount dropped | Remount: `sudo mount -a`; check [TrueNASDown](infrastructure-runbooks.md#truenasdown) |
| Docker container in bad state | `docker stop <container>; docker start <container>` |
| Backup script OOM killed | Increase swap or back up fewer containers at once |
| Disk full on /mnt/archive | Inspect retention and free space before deleting anything manually |

### Verify Recovery

```bash
ssh kagiso@10.0.10.20
cat /var/lib/node_exporter/textfile_collector/docker_backup.prom
# Timestamp should be recent
```

---

## DockerBackupSizeSuspicious

| Field | Value |
|-------|-------|
| Severity | Warning |
| Threshold | Backup size drops >50% from 7-day average, or < 10 MB |
| First Response | 2 hours |

### What This Alert Means

The Docker backup completed but the archive is significantly smaller than expected. This could mean containers were not running (so volumes were empty), the backup script skipped key directories, or the archive is corrupted.

### Diagnostic Steps

1. Check recent backup sizes:
   ```bash
   ssh kagiso@10.0.10.20
   ls -lah /mnt/archive/backups/docker/ | tail -10
   ```

2. Check what the backup script actually archives:
   ```bash
   cat /srv/docker/scripts/backup_docker.sh | grep -E "tar|exclude|BACKUP_SOURCE|BACKUP_DEST"
   ```

3. Verify key Docker volumes are non-empty:
   ```bash
   docker system df -v
   du -sh /var/lib/docker/volumes/*/
   ```

4. Test-extract the latest backup to check contents:
   ```bash
   LATEST=$(ls -t /mnt/archive/backups/docker/*.tar.gz 2>/dev/null | head -1)
   tar -tzf "$LATEST" | head -30
   ```

5. Compare with previous backup size from metric:
   ```bash
   cat /var/lib/node_exporter/textfile_collector/docker_backup.prom
   ```

### Decision Table

| Condition | Action |
|-----------|--------|
| Archive extracts fine, content looks correct | May be genuinely smaller; tune alert threshold |
| Archive is corrupt (tar fails) | Restore from previous good backup; re-run backup |
| Key volume directories missing from archive | Fix backup script to include correct paths |
| All containers were stopped | Check if intentional maintenance window |

### Verify Recovery

```bash
ssh kagiso@10.0.10.20
LATEST=$(ls -t /mnt/archive/backups/docker/*.tar.gz | head -1)
tar -tzf "$LATEST" | wc -l
# Verify file count is reasonable compared to previous backups
```

---

## RpiBackupMissing

| Field | Value |
|-------|-------|
| Severity | Warning |
| Threshold | `rpi_backup_last_success_timestamp == 0` or metric absent |
| First Response | 30 minutes |

### What This Alert Means

The RPi control hub at `10.0.10.10` has never reported a successful backup. The RPi hosts critical tooling (kubectl, flux CLI, SOPS keys) and its backup state should be known.

### Diagnostic Steps

1. SSH to the RPi:
   ```bash
   ssh kagiso@10.0.10.10
   ```

2. Check the textfile metric:
   ```bash
   cat /var/lib/node_exporter/textfile_collector/rpi_backup.prom
   ```

3. Check backup script and schedule:
   ```bash
   ls -la /usr/local/bin/rpi-backup.sh
   crontab -l | grep -i backup
   systemctl status rpi-backup.timer 2>/dev/null
   ```

4. Check available space on the SD card (RPi SD cards fill up easily):
   ```bash
   df -h /
   ```

5. Check backup destination:
   ```bash
   ls -lah /mnt/archive/rpi/ 2>/dev/null || \
   ls -lah /mnt/nas/backups/rpi/ 2>/dev/null
   ```

6. Run backup manually:
   ```bash
   sudo /usr/local/bin/rpi-backup.sh 2>&1
   ```

### Decision Table

| Condition | Action |
|-----------|--------|
| SD card >85% full | See [RpiSDCardFull](infrastructure-runbooks.md#rpisdcardfull) |
| Backup destination (NAS) unreachable | See [TrueNASDown](infrastructure-runbooks.md#truenasdown) |
| node_exporter not running | `systemctl restart node_exporter` |
| Script missing | Redeploy from GitOps repo |

### Verify Recovery

```bash
ssh kagiso@10.0.10.10
cat /var/lib/node_exporter/textfile_collector/rpi_backup.prom
ls -lah /mnt/archive/rpi/ | tail -5
```

---

## RpiBackupTooOld

| Field | Value |
|-------|-------|
| Severity | Warning |
| Threshold | `time() - rpi_backup_last_success_timestamp > 172800` (>48 hours) |
| First Response | 2 hours |

### What This Alert Means

The RPi backup has not succeeded in over 48 hours. The RPi (10.0.10.10) hosts SOPS age keys and cluster access credentials â€” a loss without a recent backup is a serious recovery impediment.

### Diagnostic Steps

1. SSH to the RPi and check the timestamp:
   ```bash
   ssh kagiso@10.0.10.10
   cat /var/lib/node_exporter/textfile_collector/rpi_backup.prom
   date +%s
   ```

2. Check if the NAS mount is up:
   ```bash
   mountpoint /mnt/archive && ls /mnt/archive/rpi/
   ```

3. Check the cron or timer:
   ```bash
   systemctl list-timers | grep rpi-backup
   crontab -l
   ```

4. Review system logs for the backup job:
   ```bash
   journalctl --since "48 hours ago" | grep -i "rpi-backup\|backup" | tail -30
   ```

5. Check SD card health (IO errors can silently fail writes):
   ```bash
   dmesg | grep -i "mmc\|mmcblk\|I/O error" | tail -20
   ```

6. Run backup manually:
   ```bash
   sudo /usr/local/bin/rpi-backup.sh 2>&1
   ```

### Decision Table

| Condition | Action |
|-----------|--------|
| dmesg shows SD card IO errors | SD card failing; see [RpiSDCardCritical](infrastructure-runbooks.md#rpisdcardcritical) |
| NAS mount missing | `sudo mount -a`; check TrueNAS availability |
| Script runs fine now | Was transient failure; monitor for recurrence |
| SOPS key backup critical | Manually copy ~/.config/sops/age/keys.txt to TrueNAS |

### Verify Recovery

```bash
ssh kagiso@10.0.10.10
cat /var/lib/node_exporter/textfile_collector/rpi_backup.prom
```

---

## VeleroBackupFailed

| Field | Value |
|-------|-------|
| Severity | Critical |
| Threshold | Velero backup status == `Failed` in last 24 hours |
| First Response | 15 minutes |

### What This Alert Means

A Velero backup job completed with a `Failed` status. Velero backs up Kubernetes resources and PVC snapshots to object storage. A failure means the cluster has no recent application-level backup.

### Diagnostic Steps

1. From the RPi control hub, check Velero backup status:
   ```bash
   ssh kagiso@10.0.10.10
   kubectl get backup -n velero --sort-by='.metadata.creationTimestamp' | tail -10
   ```

2. Get details on the failed backup:
   ```bash
   FAILED=$(kubectl get backup -n velero --field-selector=status.phase=Failed -o name | tail -1)
   kubectl describe $FAILED -n velero
   ```

3. Check Velero pod logs:
   ```bash
   kubectl logs -n velero -l app.kubernetes.io/name=velero --since=2h | grep -E "error|Error|fail|Fail" | tail -30
   ```

4. Check the backup storage location status:
   ```bash
   kubectl get backupstoragelocation -n velero
   ```

5. Check if the backup storage location is accessible (S3/MinIO/NFS):
   ```bash
   kubectl describe backupstoragelocation -n velero | grep -A5 "Status:"
   ```

6. Check node-agent (restic/kopia) DaemonSet if PVC backups are used:
   ```bash
   kubectl get daemonset -n velero
   kubectl logs -n velero -l name=node-agent --since=2h | grep -i error | tail -20
   ```

7. Attempt a manual backup:
   ```bash
   velero backup create manual-$(date +%Y%m%d-%H%M) --wait
   ```

### Decision Table

| Condition | Action |
|-----------|--------|
| BSL phase is `Unavailable` | See [VeleroBackupStorageUnavailable](#velerobackupstorageunavailable) |
| PVC snapshot failure | Check node-agent pods; check CSI snapshotter |
| Timeout errors | Increase backup timeout in VeleroSchedule spec |
| SOPS/secret errors | Verify Velero credentials secret is valid |
| Storage backend full | Prune old backups: `velero backup delete <old-backup>` |

### Verify Recovery

```bash
ssh kagiso@10.0.10.10
velero backup get | tail -5
# Confirm latest backup shows status: Completed
```

---

## VeleroBackupTooOld

| Field | Value |
|-------|-------|
| Severity | Warning |
| Threshold | No `Completed` Velero backup in last 25 hours |
| First Response | 1 hour |

### What This Alert Means

Velero has not completed a successful backup in over 25 hours. The scheduled backup is failing silently or the schedule itself has been removed/suspended.

### Diagnostic Steps

1. Check existing backups and their ages:
   ```bash
   ssh kagiso@10.0.10.10
   kubectl get backup -n velero --sort-by='.metadata.creationTimestamp' | tail -10
   ```

2. Check the Velero schedule exists and is not paused:
   ```bash
   kubectl get schedule -n velero
   kubectl describe schedule -n velero | grep -E "Paused|Last Backup|Schedule:"
   ```

3. Check Velero controller logs for scheduling errors:
   ```bash
   kubectl logs -n velero -l app.kubernetes.io/name=velero --since=26h | grep -i "schedule\|error" | tail -30
   ```

4. Verify backup storage location is available:
   ```bash
   kubectl get backupstoragelocation -n velero
   ```

5. Check if Flux has suspended or altered the Velero deployment:
   ```bash
   kubectl get helmrelease -n velero
   flux get helmreleases -n velero
   ```

### Decision Table

| Condition | Action |
|-----------|--------|
| Schedule paused | `kubectl patch schedule <name> -n velero --type=merge -p '{"spec":{"paused":false}}'` |
| Schedule deleted | Re-apply from GitOps: `flux reconcile kustomization velero` |
| BSL unavailable | See [VeleroBackupStorageUnavailable](#velerobackupstorageunavailable) |
| Backups running but all fail | See [VeleroBackupFailed](#velerobackupfailed) |

### Verify Recovery

```bash
ssh kagiso@10.0.10.10
velero backup get | grep Completed | tail -3
```

---

## VeleroBackupStorageUnavailable

| Field | Value |
|-------|-------|
| Severity | Critical |
| Threshold | `BackupStorageLocation` phase != `Available` for >5 minutes |
| First Response | 15 minutes |

### What This Alert Means

Velero cannot reach its backup storage backend (S3-compatible object store, NFS, or MinIO). All backups will fail until this is resolved. This is a critical gap in data protection.

### Diagnostic Steps

1. Check BSL status:
   ```bash
   ssh kagiso@10.0.10.10
   kubectl get backupstoragelocation -n velero -o wide
   kubectl describe backupstoragelocation -n velero
   ```

2. Get the backend endpoint from the BSL spec:
   ```bash
   kubectl get backupstoragelocation -n velero -o jsonpath='{.items[0].spec.config.s3Url}'
   ```

3. Check connectivity to the storage backend from within the cluster:
   ```bash
   kubectl run -n velero -it --rm debug --image=curlimages/curl --restart=Never -- \
     curl -v http://<storage-endpoint>/
   ```

4. If backend is MinIO on TrueNAS (10.0.10.80), check it:
   ```bash
   curl -I http://10.0.10.80:9000/minio/health/live
   ssh admin@10.0.10.80 "docker ps | grep minio" 2>/dev/null
   ```

5. Verify Velero credentials secret is intact:
   ```bash
   kubectl get secret -n velero velero-credentials -o jsonpath='{.data.cloud}' | base64 -d
   ```

6. Check Velero BSL controller logs:
   ```bash
   kubectl logs -n velero -l app.kubernetes.io/name=velero --since=1h | grep -i "backup storage\|BSL\|unavailable" | tail -20
   ```

7. If using TrueNAS NFS for backup storage, verify NFS mount on the relevant node:
   ```bash
   ssh kagiso@10.0.10.11  # or whichever node runs Velero pod
   mount | grep nfs
   ```

### Decision Table

| Condition | Action |
|-----------|--------|
| TrueNAS is down | See [TrueNASDown](infrastructure-runbooks.md#truenasdown) |
| MinIO container not running | Restart MinIO on TrueNAS via TrueNAS UI or SSH |
| Credentials invalid | Re-create secret from SOPS-encrypted source in GitOps |
| NFS mount dropped | `sudo mount -a` on affected node |
| Network issue to 10.0.10.80 | Check switch/VLAN; ping from each k3s node |

### Verify Recovery

```bash
ssh kagiso@10.0.10.10
kubectl get backupstoragelocation -n velero
# Phase should show: Available
velero backup create bsl-verify-$(date +%Y%m%d) --wait
```
