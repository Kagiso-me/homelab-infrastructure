# TrueNAS and Disk Health Alert Runbooks

| Field | Value |
|-------|-------|
| File | truenas-runbooks.md |
| Covers | ZFSPoolDegraded, ZFSPoolFaulted, ZFSPoolUnavail, ZFSPoolScrubErrors, ZFSPoolChecksumErrors, ZFSScrubNotRun, DiskSMARTFailed, DiskReallocatedSectors, DiskReallocatedSectorsCritical, DiskPendingSectors, DiskUncorrectableSectors, DiskTemperatureHigh, DiskTemperatureCritical, DiskSpinRetryCount, DiskCRCErrors, SmartctlExporterDown |
| Last Updated | 2026-03-15 |

**Quick Reference:**
- TrueNAS SCALE UI: http://10.0.10.80
- TrueNAS SSH: `ssh admin@10.0.10.80`
- ZFS Pool Names: `core` (k8s PVCs), `archive` (backups), `tera` (media)
- Check pool status: `zpool status`
- Check disk SMART: `smartctl -a /dev/sdX`
- List disks: `lsblk` or `ls /dev/sd*`

---

## Table of Contents

1. [ZFSPoolDegraded](#zpoolpooldegraded)
2. [ZFSPoolFaulted](#zpoolpoolfaulted)
3. [ZFSPoolUnavail](#zpoolpoolavail)
4. [ZFSPoolScrubErrors](#zpoolpoolscrubberrors)
5. [ZFSPoolChecksumErrors](#zpoolpoolchecksumerrors)
6. [ZFSScrubNotRun](#zfsscrubnotrun)
7. [DiskSMARTFailed](#disksmartfailed)
8. [DiskReallocatedSectors](#diskreallocatedsectors)
9. [DiskReallocatedSectorsCritical](#diskreallocatedsectorscritical)
10. [DiskPendingSectors](#diskpendingsectors)
11. [DiskUncorrectableSectors](#diskuncorrectablesectors)
12. [DiskTemperatureHigh](#disktemperaturehigh)
13. [DiskTemperatureCritical](#disktemperaturecritical)
14. [DiskSpinRetryCount](#diskspinretrycount)
15. [DiskCRCErrors](#diskcrcerrors)
16. [SmartctlExporterDown](#smartctlexporterdown)

---

## ZFSPoolDegraded

| Field | Value |
|-------|-------|
| Severity | Critical |
| Threshold | `zpool_pool_health` != ONLINE (DEGRADED state) |
| First Response | 10 minutes |

### What This Alert Means

The affected ZFS pool is in a DEGRADED state, meaning one or more member disks have been removed, failed, or are reporting errors. ZFS is still operational and serving data via its redundancy, but any further disk failure may result in data loss. This is a race condition — act quickly.

### Diagnostic Steps

1. SSH to TrueNAS and check the pool status immediately:
   ```bash
   ssh admin@10.0.10.80
   zpool status
   ```
   Look for: `state: DEGRADED`, and in the disk layout which disk shows `FAULTED`, `REMOVED`, or `UNAVAIL`.

2. Identify the specific failing disk:
   ```bash
   zpool status | grep -E "FAULTED|REMOVED|UNAVAIL|DEGRADED|errors:"
   ```

3. Get the disk device path for the failing disk:
   ```bash
   # zpool status shows the disk by ID, find its /dev/sdX path:
   ls -la /dev/disk/by-id/ | grep <disk-id-from-zpool-status>
   # Or:
   lsblk -o NAME,SIZE,MODEL,SERIAL
   ```

4. Check if the disk is still visible to the OS:
   ```bash
   lsblk
   ls /dev/sd*
   dmesg | grep -i "error\|I/O error\|reset\|exception" | tail -30
   ```

5. Run a SMART test on the suspect disk to assess its health:
   ```bash
   smartctl -a /dev/sdX  # replace sdX with failing disk
   smartctl -t short /dev/sdX
   # Wait ~2 minutes, then:
   smartctl -a /dev/sdX | grep -E "SMART overall|Reallocated|Pending|Uncorrectable|Spin_Retry"
   ```

6. Check SMART test results and recent errors:
   ```bash
   smartctl -a /dev/sdX | grep -A5 "SMART Error Log"
   ```

7. Attempt to online/clear the disk if it was temporarily removed:
   ```bash
   zpool online <pool> /dev/sdX
   zpool clear <pool>
   zpool status  # Check if it recovers
   ```

8. If disk is confirmed failed, initiate resilver after physical replacement:
   ```bash
   # After inserting new disk:
   zpool replace <pool> /dev/sdX_old /dev/sdY_new
   zpool status  # Watch resilver progress
   ```

### Decision Table

| Condition | Action |
|-----------|--------|
| Disk FAULTED, SMART shows errors | Plan disk replacement; see [node-replacement.md](../node-replacement.md) |
| Disk REMOVED (hot-swap mishap) | Reseat disk; `zpool online <pool> /dev/sdX` |
| Disk shows checksum errors only | Monitor; run scrub; may be cable issue |
| DEGRADED with no obvious cause | Check cables/HBA; check dmesg for controller errors |
| Second disk showing errors | Urgent: backup all data immediately before replacing first |

### Verify Recovery

```bash
ssh admin@10.0.10.80
zpool status | grep "state:"
# state: ONLINE
# pool should show no errors and either all disks ONLINE or resilver complete
```

---

## ZFSPoolFaulted

| Field | Value |
|-------|-------|
| Severity | Critical |
| Threshold | `zpool_pool_health` == FAULTED |
| First Response | Immediate (5 minutes) |

### What This Alert Means

The affected ZFS pool is FAULTED. This is more severe than DEGRADED — the pool cannot satisfy its redundancy requirements and may not be serving data. This could mean multiple simultaneous disk failures or a catastrophic event. All NFS exports from TrueNAS are likely offline.

### Diagnostic Steps

1. SSH immediately to TrueNAS:
   ```bash
   ssh admin@10.0.10.80
   zpool status
   ```

2. Note exactly how many disks are FAULTED/UNAVAIL and what the vdev layout is (mirror, RAIDZ1, RAIDZ2, etc.).

3. Check if the pool is still importable:
   ```bash
   zpool status
   zpool list
   ```

4. Check dmesg for disk controller/IO errors:
   ```bash
   dmesg | grep -i "error\|I/O\|ata\|sata\|hba" | tail -50
   journalctl -k --since "2 hours ago" | grep -i "error\|disk\|scsi" | tail -30
   ```

5. Determine if this is a power/cable issue vs. true disk failure:
   ```bash
   # All disks visible?
   lsblk | grep sd
   # Compare count to expected number of disks in pool
   ```

6. Attempt emergency pool export/import (may recover from transient faults):
   ```bash
   # WARNING: Only if pool is not currently serving data or you've stopped all NFS
   zpool export <pool>
   zpool import <pool>
   zpool status
   ```

7. If data is accessible (pool recovers after import), immediately back up critical data:
   ```bash
   # From RPi, trigger all backup jobs:
   ssh kagiso@10.0.10.32 "sudo /usr/local/bin/docker-backup.sh" &
   ssh kagiso@10.0.10.11 "sudo /usr/local/bin/etcd-backup.sh" &
   ```

8. See [cluster-rebuild.md](../cluster-rebuild.md) if this escalates to full recovery scenario.

### Decision Table

| Condition | Action |
|-----------|--------|
| Multiple disks FAULTED | Potential data loss; invoke [backup-restoration.md](../backup-restoration.md) |
| All disks visible but pool FAULTED | Try zpool export/import; may be metadata corruption |
| Power event preceded fault | Check PSU; reseat all drives; reimport pool |
| Single disk FAULTED in RAIDZ1 | Degraded but recoverable — treat as [ZFSPoolDegraded](#zpoolpooldegraded) |

### Verify Recovery

```bash
ssh admin@10.0.10.80
zpool status | grep "state:"
# state must be ONLINE or DEGRADED (not FAULTED)
# Then verify NFS is accessible:
ssh kagiso@10.0.10.32 "ls /mnt/archive/ | head -3"
```

---

## ZFSPoolUnavail

| Field | Value |
|-------|-------|
| Severity | Critical |
| Threshold | `zpool_pool_health` == UNAVAIL |
| First Response | Immediate (5 minutes) |

### What This Alert Means

The affected ZFS pool is completely UNAVAILABLE. No data can be read or written. This typically occurs when all paths to the pool's disks are lost, TrueNAS itself has crashed/rebooted, or the pool was force-exported. All NFS exports and data services are offline.

### Diagnostic Steps

1. First, confirm TrueNAS itself is responsive:
   ```bash
   ssh kagiso@10.0.10.10
   ping -c 4 10.0.10.80
   ssh -o ConnectTimeout=10 admin@10.0.10.80
   ```

2. If TrueNAS is SSH-accessible:
   ```bash
   ssh admin@10.0.10.80
   zpool status
   zpool list
   # Check if pool shows UNAVAIL or is missing entirely
   ```

3. If pool is missing from `zpool list`, try importing it:
   ```bash
   zpool import
   # This will show pools available for import
   zpool import <pool>
   zpool status
   ```

4. Check if disks are visible:
   ```bash
   lsblk
   ls /dev/sd* | wc -l
   # Compare to number of disks you expect
   ```

5. If TrueNAS is unreachable, check physical host:
   - TrueNAS UI at http://10.0.10.80
   - Physical console if available
   - Power status

6. Check for filesystem errors that may have triggered an automatic export:
   ```bash
   journalctl -k --since "1 hour ago" | grep -i "zfs\|zpool\|unavail" | tail -30
   ```

### Decision Table

| Condition | Action |
|-----------|--------|
| TrueNAS crashed and rebooted | Pool should auto-import on boot; wait and verify |
| Pool not auto-imported after reboot | `zpool import <pool>` manually |
| All disks missing | HBA/controller failure; physical inspection required |
| TrueNAS completely down | See [TrueNASDown](infrastructure-runbooks.md#truenasdown) |

### Verify Recovery

```bash
ssh admin@10.0.10.80
zpool status | grep "state:"
# state: ONLINE
```

---

## ZFSPoolScrubErrors

| Field | Value |
|-------|-------|
| Severity | Warning |
| Threshold | Scrub completed with read/write errors > 0 |
| First Response | 2 hours |

### What This Alert Means

The most recent ZFS scrub found data errors. A scrub reads every block in the pool and verifies checksums. Errors during scrub indicate either bad data on disk (which ZFS may have repaired from parity) or a disk that cannot reliably read/write. This warrants disk investigation.

### Diagnostic Steps

1. Check the scrub results:
   ```bash
   ssh admin@10.0.10.80
   zpool status | grep -A20 "scan:"
   # Look for: "repaired" and "errors" counts
   ```

2. Identify which disk had errors:
   ```bash
   zpool status | grep -E "ONLINE|DEGRADED|errors:"
   # Look for disks that show non-zero error counts in READ/WRITE/CKSUM columns
   ```

3. Run a full SMART test on the disk(s) with errors:
   ```bash
   # First, identify the disk:
   zpool status -v | grep "errors: [^0]"
   # Get the device path:
   ls -la /dev/disk/by-id/ | grep <disk-id>

   # Run extended SMART test (takes 2-6 hours for large drives):
   smartctl -t long /dev/sdX

   # Check progress after starting:
   smartctl -a /dev/sdX | grep "Test remaining"
   ```

4. Check for any existing SMART errors before the test completes:
   ```bash
   smartctl -a /dev/sdX | grep -E "Reallocated|Pending|Uncorrectable|Spin_Retry|CRC"
   ```

5. Check if ZFS auto-repaired the data (repaired count > 0 means data was corrupted but fixed):
   ```bash
   zpool status | grep "repaired"
   ```

6. If errors were repaired: data is now consistent, but the disk is suspect. If errors were NOT repaired: data may be permanently lost for those blocks.

7. Clear error counters after investigation (to track new errors going forward):
   ```bash
   zpool clear <pool>
   ```

### Decision Table

| Condition | Action |
|-----------|--------|
| Errors repaired, SMART healthy | Disk is marginal; run scrubs more frequently; monitor |
| Errors NOT repaired | Data loss has occurred; restore affected files from backup |
| SMART shows Reallocated sectors | See [DiskReallocatedSectors](#diskreallocatedsectors) |
| Multiple disks showing errors | Check SATA cables and HBA; may be controller issue |
| Recurring scrub errors | Plan disk replacement |

### Verify Recovery

```bash
ssh admin@10.0.10.80
# Run a new scrub after clearing errors:
zpool scrub core && zpool scrub archive && zpool scrub tera
# Monitor progress:
zpool status | grep "scan:"
# Final state should show 0 errors
```

---

## ZFSPoolChecksumErrors

| Field | Value |
|-------|-------|
| Severity | Warning |
| Threshold | Checksum error count increases between scrubs (per-disk CKSUM column > 0) |
| First Response | 2 hours |

### What This Alert Means

ZFS has detected data that does not match its recorded checksum on one or more disks. This can be caused by a failing disk, faulty SATA cable, dodgy HBA controller, or (rarely) cosmic ray bit-flips. ZFS may be able to self-heal from parity, but the root cause must be found.

### Diagnostic Steps

1. Check which disk is generating checksum errors:
   ```bash
   ssh admin@10.0.10.80
   zpool status
   # In the NAME/STATE/READ/WRITE/CKSUM table, identify the disk with non-zero CKSUM
   ```

2. Check if errors are isolated to one disk or spread across all:
   ```bash
   zpool status -v
   ```

3. Test the SATA cable first (cheapest fix if errors are on one disk):
   - Swap the SATA cable on the suspect disk with a known-good cable
   - Run `zpool clear <pool>` and monitor for new errors

4. Check the disk's SMART data:
   ```bash
   smartctl -a /dev/sdX | grep -E "Reallocated|Uncorrect|CRC|UDMA"
   ```

   High CRC errors = cable/controller issue. Reallocated sectors = disk issue.

5. Check the HBA or SATA controller:
   ```bash
   dmesg | grep -i "ata\|sata\|ahci\|error\|exception" | tail -30
   ```

6. Run a scrub to see if errors persist after clearing:
   ```bash
   zpool clear <pool>
   zpool scrub core && zpool scrub archive && zpool scrub tera
   # Check status after scrub completes
   ```

### Decision Table

| Condition | Action |
|-----------|--------|
| Errors on one disk, CRC errors in SMART | Replace SATA cable first |
| Errors spread across all disks | Check HBA; replace controller if faulty |
| Errors on one disk, Reallocated sectors | Disk is failing; see [DiskReallocatedSectors](#diskreallocatedsectors) |
| Errors clear after cable swap | Was cable issue; monitor for recurrence |

### Verify Recovery

```bash
ssh admin@10.0.10.80
zpool clear <pool>
zpool scrub core && zpool scrub archive && zpool scrub tera
# After scrub completes:
zpool status | grep "scan:"
# Should show 0 checksum errors
```

---

## ZFSScrubNotRun

| Field | Value |
|-------|-------|
| Severity | Warning |
| Threshold | No ZFS scrub completed in the last 35 days |
| First Response | 4 hours |

### What This Alert Means

A ZFS pool scrub has not been run in over 35 days. Regular scrubs are essential for detecting silent data corruption (bit rot) early. Without scrubs, data errors accumulate undetected until they spread or become unrecoverable.

### Diagnostic Steps

1. Check when the last scrub ran:
   ```bash
   ssh admin@10.0.10.80
   zpool status | grep "scan:"
   # Shows last scrub date and result
   ```

2. Check if automatic scrub is scheduled in TrueNAS:
   ```bash
   # Via TrueNAS UI: Data Protection → Scrub Tasks
   # Or via CLI:
   midclt call pool.scrub.query | python3 -m json.tool
   ```

3. Check if the scrub schedule cron exists:
   ```bash
   crontab -l | grep scrub
   # Or check TrueNAS's task scheduler:
   midclt call core.get_jobs | python3 -m json.tool | grep -i scrub
   ```

4. Run a scrub manually now:
   ```bash
   zpool scrub core && zpool scrub archive && zpool scrub tera
   # Monitor progress (check every few minutes):
   watch -n 30 "zpool status | grep -A5 'scan:'"
   ```

5. If TrueNAS task was deleted or disabled, recreate it:
   - TrueNAS UI → Data Protection → Scrub Tasks → Add
   - Set pool: `core`, `archive`, or `tera`,; run scrubs on all pools: `zpool scrub core`, `zpool scrub archive`, `zpool scrub tera`

### Verify Recovery

```bash
ssh admin@10.0.10.80
zpool status | grep "scan:"
# Should show: "scrub repaired X in HH:MM:SS with 0 errors on <recent date>"
```

---

## DiskSMARTFailed

| Field | Value |
|-------|-------|
| Severity | Critical |
| Threshold | `smartctl_device_smart_healthy == 0` (SMART overall health FAILED) |
| First Response | 15 minutes |

### What This Alert Means

A disk in the TrueNAS system has a SMART overall health assessment of FAILED. This is the disk's own prediction that it will fail within 24 hours. Treat this as imminent disk failure — data loss is likely without immediate action.

### Diagnostic Steps

1. Identify the failing disk:
   ```bash
   ssh admin@10.0.10.80
   for disk in /dev/sd*; do
     echo -n "$disk: "
     smartctl -H $disk | grep "SMART overall-health"
   done
   ```

2. Get full SMART details on the failing disk:
   ```bash
   smartctl -a /dev/sdX
   ```

3. Identify which ZFS vdev this disk belongs to:
   ```bash
   zpool status
   # Match disk serial number from SMART output to disk ID in zpool status
   ```

4. Check the pool state — is it still online?
   ```bash
   zpool status | grep "state:"
   ```

5. Immediately create a backup of critical data:
   ```bash
   # Send ZFS snapshot to another dataset or remote location if possible:
   zfs snapshot -r <pool>@emergency-$(date +%Y%m%d-%H%M)
   zfs list -t snapshot | grep emergency
   ```

6. If pool allows, begin disk replacement process now:
   ```bash
   # Identify replacement disk (must be same size or larger):
   lsblk
   # Physically install new disk, then:
   zpool replace <pool> /dev/sdX_failing /dev/sdY_new
   zpool status  # Watch resilver progress
   ```

7. Notify that a new disk needs to be ordered/sourced immediately if no spare is available.

### Decision Table

| Condition | Action |
|-----------|--------|
| Pool is DEGRADED or FAULTED | See [ZFSPoolDegraded](#zpoolpooldegraded) or [ZFSPoolFaulted](#zpoolpoolfaulted) |
| Pool still ONLINE, disk SMART FAILED | Replace disk immediately while pool is still redundant |
| No spare disk available | Order one urgently; do NOT power cycle the NAS |
| Other disks showing pre-failure SMART | See [DiskReallocatedSectors](#diskreallocatedsectors) — may need multiple replacements |

### Verify Recovery

```bash
ssh admin@10.0.10.80
zpool status | grep "state:"
# state: ONLINE (after resilver completes)
smartctl -H /dev/sdY_new | grep "SMART overall-health"
# SMART overall-health self-assessment test result: PASSED
```

---

## DiskReallocatedSectors

| Field | Value |
|-------|-------|
| Severity | Warning |
| Threshold | SMART attribute 5 (Reallocated_Sector_Ct) > 0 |
| First Response | 4 hours |

### What This Alert Means

A disk has begun remapping bad sectors to spare sectors. A small number (< 10) can be normal early in a disk's life, but any increase over time indicates the disk is failing. The disk has found areas it cannot reliably write to and has compensated, but spare sectors are finite.

### Diagnostic Steps

1. Check which disk has reallocated sectors:
   ```bash
   ssh admin@10.0.10.80
   for disk in /dev/sd*; do
     count=$(smartctl -A $disk | grep "Reallocated_Sector_Ct" | awk '{print $10}')
     if [ -n "$count" ] && [ "$count" -gt "0" ]; then
       echo "$disk: Reallocated=$count"
     fi
   done
   ```

2. Get the full SMART attribute table for the disk:
   ```bash
   smartctl -A /dev/sdX
   # Focus on: ID 5 (Reallocated_Sector_Ct), ID 196 (Reallocated_Event_Count),
   #           ID 197 (Current_Pending_Sector), ID 198 (Offline_Uncorrectable)
   ```

3. Check the raw value and trend (is it growing?):
   ```bash
   smartctl -a /dev/sdX | grep -E "Reallocated|Pending|Uncorrectable"
   # Compare to last week's values if logged in Prometheus
   ```

4. Run a short SMART self-test to check current disk health:
   ```bash
   smartctl -t short /dev/sdX
   # Wait 2 minutes:
   smartctl -a /dev/sdX | grep -A5 "Self-test execution"
   ```

5. Check which ZFS vdev this disk belongs to:
   ```bash
   zpool status -v
   ```

6. Run a ZFS scrub to see if reallocated sectors are causing checksum errors:
   ```bash
   zpool scrub core && zpool scrub archive && zpool scrub tera
   # After completion:
   zpool status | grep "scan:"
   ```

### Decision Table

| Condition | Action |
|-----------|--------|
| Count is small (1-5) and stable | Monitor monthly; no immediate action required |
| Count > 10 or growing | Plan disk replacement within 2 weeks |
| Count growing rapidly | See [DiskReallocatedSectorsCritical](#diskreallocatedsectorscritical) |
| Also shows pending sectors | See [DiskPendingSectors](#diskpendingsectors) — escalate urgency |
| SMART test FAILED | See [DiskSMARTFailed](#disksmartfailed) |

### Verify Recovery

```bash
ssh admin@10.0.10.80
smartctl -A /dev/sdX | grep "Reallocated_Sector_Ct"
# After disk replacement, new disk should show: 0 reallocated sectors
zpool status | grep "state:"
# state: ONLINE
```

---

## DiskReallocatedSectorsCritical

| Field | Value |
|-------|-------|
| Severity | Critical |
| Threshold | SMART attribute 5 (Reallocated_Sector_Ct) > 50 |
| First Response | 30 minutes |

### What This Alert Means

A disk has reallocated more than 50 sectors. At this count the disk is actively failing. The spare sector pool is being consumed and the disk may start failing to remap new bad sectors, leading to unrecoverable read errors and potential data loss.

### Diagnostic Steps

1. Confirm the count and identify the disk:
   ```bash
   ssh admin@10.0.10.80
   smartctl -A /dev/sdX | grep -E "Reallocated|Pending|Uncorrectable"
   smartctl -H /dev/sdX | grep "overall-health"
   ```

2. Check for pending sectors (sectors that have read errors but haven't been reallocated yet):
   ```bash
   smartctl -A /dev/sdX | grep "Current_Pending_Sector"
   ```

3. Check ZFS pool status for this disk's error counters:
   ```bash
   zpool status -v | grep "sdX"
   ```

4. Create an emergency ZFS snapshot immediately:
   ```bash
   zfs snapshot -r <pool>@pre-disk-replace-$(date +%Y%m%d-%H%M)
   ```

5. Begin disk replacement — treat this as urgent:
   ```bash
   # If a replacement disk is available and pool has redundancy:
   zpool replace <pool> /dev/sdX /dev/sdY_new
   # Watch resilver:
   watch -n 60 "zpool status | grep -E 'resilver|scan:|sdX|sdY'"
   ```

6. If no replacement disk is available:
   - Order immediately
   - Increase scrub frequency: `zpool scrub core && zpool scrub archive && zpool scrub tera` daily
   - Monitor disk SMART every few hours
   - Do NOT run tasks that stress-write to this disk

### Verify Recovery

```bash
ssh admin@10.0.10.80
zpool status | grep "state:"
# state: ONLINE after resilver completes
smartctl -H /dev/sdY_new | grep "overall-health"
# PASSED
```

---

## DiskPendingSectors

| Field | Value |
|-------|-------|
| Severity | Warning |
| Threshold | SMART attribute 197 (Current_Pending_Sector) > 0 |
| First Response | 1 hour |

### What This Alert Means

A disk has sectors that have been read with errors and are "pending" reallocation. The disk will try to write to these sectors again; if the write succeeds, the sector is cleared; if not, it gets reallocated. Pending sectors indicate the disk has areas it cannot reliably read — those sectors may contain unreadable data.

### Diagnostic Steps

1. Identify the disk and count:
   ```bash
   ssh admin@10.0.10.80
   for disk in /dev/sd*; do
     val=$(smartctl -A $disk | awk '/Current_Pending_Sector/{print $10}')
     [ -n "$val" ] && [ "$val" -gt "0" ] && echo "$disk: Pending=$val"
   done
   ```

2. Get full SMART picture:
   ```bash
   smartctl -A /dev/sdX | grep -E "Reallocated|Pending|Uncorrectable|Spin_Retry"
   ```

3. Run a ZFS scrub — ZFS will attempt to read/repair affected blocks:
   ```bash
   zpool scrub core && zpool scrub archive && zpool scrub tera
   # After completion, check if ZFS found errors:
   zpool status | grep "scan:"
   ```

4. After the scrub, re-check pending sector count:
   ```bash
   smartctl -A /dev/sdX | grep "Current_Pending_Sector"
   # If count decreased: ZFS repaired some blocks by rewriting them
   # If count increased: disk is actively failing
   ```

5. Check if any files may have been affected:
   ```bash
   # Look for ZFS checksum errors on this disk:
   zpool status -v | grep "sdX"
   ```

### Decision Table

| Condition | Action |
|-----------|--------|
| Count is 1-3, scrub resolves it | Disk recovering; monitor weekly |
| Count unchanged after scrub | Disk sectors unrecoverable; plan replacement |
| Count growing | Treat as [DiskReallocatedSectorsCritical](#diskreallocatedsectorscritical) |
| ZFS scrub found errors | Check if data was repaired or lost |

### Verify Recovery

```bash
ssh admin@10.0.10.80
smartctl -A /dev/sdX | grep "Current_Pending_Sector"
# Should be 0 or decreasing
zpool status | grep "scan:"
# Scrub should show 0 errors if pool parity was able to recover data
```

---

## DiskUncorrectableSectors

| Field | Value |
|-------|-------|
| Severity | Critical |
| Threshold | SMART attribute 198 (Offline_Uncorrectable) > 0 |
| First Response | 30 minutes |

### What This Alert Means

A disk has sectors that have permanently failed and cannot be read or written. Data that was stored in these sectors is likely lost (unless ZFS can reconstruct it from parity). This indicates significant disk failure and the disk must be replaced.

### Diagnostic Steps

1. Confirm the count and disk identity:
   ```bash
   ssh admin@10.0.10.80
   smartctl -A /dev/sdX | grep "Offline_Uncorrectable"
   smartctl -H /dev/sdX | grep "overall-health"
   ```

2. Determine if ZFS can recover the data from parity (depends on pool redundancy):
   ```bash
   zpool status | grep "state:"
   # If DEGRADED already: data loss may have occurred
   zpool status -v | grep "sdX"  # Check error counters for this disk
   ```

3. Run a scrub immediately to assess damage:
   ```bash
   zpool scrub core && zpool scrub archive && zpool scrub tera
   # After completion:
   zpool status | grep "scan:"
   # "repaired X" = ZFS fixed it from parity
   # "errors: X" = data is unrecoverable
   ```

4. If ZFS shows unrecoverable errors — identify affected files:
   ```bash
   # ZFS doesn't directly tell you which files were affected,
   # but you can check zpool status for the vdev:
   zpool status -v
   ```

5. Begin immediate disk replacement:
   ```bash
   # Install replacement disk, then:
   zpool replace <pool> /dev/sdX /dev/sdY_new
   watch -n 60 "zpool status | grep -E 'resilver|scan:'"
   ```

6. If data loss occurred, restore from backups:
   - See [backup-restoration.md](../backup-restoration.md)

### Verify Recovery

```bash
ssh admin@10.0.10.80
zpool status | grep "state:"
# state: ONLINE (after resilver)
zpool scrub core && zpool scrub archive && zpool scrub tera
# After scrub: scan: scrub repaired 0 in ... with 0 errors
```

---

## DiskTemperatureHigh

| Field | Value |
|-------|-------|
| Severity | Warning |
| Threshold | Disk temperature > 45°C |
| First Response | 2 hours |

### What This Alert Means

One or more disks in the TrueNAS system are running above 45°C. Hard drives operate best between 20-45°C. Sustained high temperatures accelerate wear and can trigger SMART thermal events that put the disk into a protection mode.

### Diagnostic Steps

1. Check temperatures of all disks:
   ```bash
   ssh admin@10.0.10.80
   for disk in /dev/sd*; do
     temp=$(smartctl -A $disk | awk '/Temperature_Celsius/{print $10}')
     echo "$disk: ${temp}°C"
   done
   ```

2. Check ambient temperature and airflow:
   - Is the case/enclosure properly ventilated?
   - Are drive bays packed too tightly?
   - Is the room/server closet hot?

3. Check fan status on TrueNAS:
   ```bash
   # Via TrueNAS UI: System → Reporting → CPU Temperature, or use IPMI if available
   ipmitool sdr type Fan 2>/dev/null || echo "IPMI not available"
   ```

4. Check if a specific disk is hotter than others (localized airflow issue):
   ```bash
   for disk in /dev/sd*; do
     echo -n "$disk $(lsblk -no MODEL $disk 2>/dev/null): "
     smartctl -A $disk | awk '/Temperature_Celsius/{print $10"°C"}'
   done
   ```

5. Review SMART temperature history:
   ```bash
   smartctl -a /dev/sdX | grep -A5 "Temperature"
   ```

### Decision Table

| Condition | Action |
|-----------|--------|
| All disks hot | Room temperature issue; improve ventilation |
| One disk hotter than others | Airflow blockage near that bay; check cable routing |
| Fan failure | Replace fan; ensure all fans spinning |
| Temperature rising over time | Bearing failure in drive bay fan; act before [DiskTemperatureCritical](#disktemperaturecritical) |

### Verify Recovery

```bash
ssh admin@10.0.10.80
for disk in /dev/sd*; do
  echo -n "$disk: "
  smartctl -A $disk | awk '/Temperature_Celsius/{print $10"°C"}'
done
# All disks should be below 45°C
```

---

## DiskTemperatureCritical

| Field | Value |
|-------|-------|
| Severity | Critical |
| Threshold | Disk temperature > 55°C |
| First Response | 15 minutes |

### What This Alert Means

A disk is at or above 55°C. Most hard drives have a maximum rated operating temperature of 60°C. At this temperature, drive failure rate increases significantly. The drive may also throttle IO, causing system-wide slowdowns.

### Diagnostic Steps

1. Immediately check which disk(s) are critically hot:
   ```bash
   ssh admin@10.0.10.80
   for disk in /dev/sd*; do
     temp=$(smartctl -A $disk | awk '/Temperature_Celsius/{print $10}')
     [ -n "$temp" ] && [ "$temp" -gt "50" ] && echo "CRITICAL: $disk: ${temp}°C"
   done
   ```

2. Check if the disk is still operational (SMART health):
   ```bash
   smartctl -H /dev/sdX | grep "overall-health"
   ```

3. Consider reducing load on this disk while resolving the thermal issue:
   ```bash
   # Reduce scrub if running:
   zpool scrub -p <pool>  # pause scrub
   ```

4. Investigate cooling immediately:
   - Check all fans in the system are spinning
   - Ensure the NAS has adequate airflow around it
   - Temporarily increase room airflow (open server closet door, add a fan)

5. If temperature does not drop within 30 minutes, plan for graceful shutdown to prevent disk damage:
   ```bash
   # Alert others first, then:
   # Via TrueNAS UI: System → Shutdown
   # Or CLI:
   poweroff
   ```

### Decision Table

| Condition | Action |
|-----------|--------|
| Fan failure confirmed | Physical repair; do not run NAS without cooling |
| No fan failure (environmental) | Immediate room cooling; consider graceful shutdown |
| Temperature dropping | Continue monitoring; fix root cause |
| Temperature stable at 55°C+ for >30min | Graceful shutdown to prevent hardware damage |

### Verify Recovery

```bash
ssh admin@10.0.10.80
for disk in /dev/sd*; do
  echo -n "$disk: "
  smartctl -A $disk | awk '/Temperature_Celsius/{print $10"°C"}'
done
# All disks below 45°C
```

---

## DiskSpinRetryCount

| Field | Value |
|-------|-------|
| Severity | Warning |
| Threshold | SMART attribute 10 (Spin_Retry_Count) > 0 |
| First Response | 2 hours |

### What This Alert Means

A disk is having difficulty spinning up to operating speed within the expected time window. This can indicate motor bearing problems, insufficient power delivery, or a disk on the verge of failure. Spin retry events put stress on the motor.

### Diagnostic Steps

1. Identify the disk with spin retry events:
   ```bash
   ssh admin@10.0.10.80
   for disk in /dev/sd*; do
     val=$(smartctl -A $disk | awk '/Spin_Retry_Count/{print $10}')
     [ -n "$val" ] && [ "$val" -gt "0" ] && echo "$disk: Spin_Retry=$val"
   done
   ```

2. Get the full SMART picture:
   ```bash
   smartctl -a /dev/sdX | grep -E "Spin_Up_Time|Spin_Retry|Start_Stop_Count|Power_On_Hours"
   ```

3. Check power supply capacity — spin-up draws high current:
   ```bash
   # Check if multiple drives are spinning up simultaneously at boot (staggered spin-up helps)
   # TrueNAS UI: Storage → Disks → check for "advanced power management" settings
   ```

4. Check the disk's spin-up time compared to spec:
   ```bash
   smartctl -A /dev/sdX | grep "Spin_Up_Time"
   # Normal is typically 400-3000ms; very high values indicate motor issues
   ```

5. Verify the disk is in the ZFS pool and check for read errors:
   ```bash
   zpool status -v | grep "sdX"
   ```

6. Run a short SMART test:
   ```bash
   smartctl -t short /dev/sdX
   # After 2 minutes:
   smartctl -a /dev/sdX | grep -A5 "Self-test execution"
   ```

### Decision Table

| Condition | Action |
|-----------|--------|
| Count is small (1-3) and stable | Monitor; may be a one-time power event |
| Count increasing | Motor bearing issue; plan replacement within 1 month |
| Disk also has pending/reallocated sectors | Accelerate replacement timeline |
| Multiple disks with spin retries | Check PSU capacity for full disk spin-up load |

### Verify Recovery

```bash
ssh admin@10.0.10.80
# After replacing disk:
smartctl -A /dev/sdY_new | grep "Spin_Retry_Count"
# Should be 0
```

---

## DiskCRCErrors

| Field | Value |
|-------|-------|
| Severity | Warning |
| Threshold | SMART attribute 199 (UDMA_CRC_Error_Count) > 0 or increasing |
| First Response | 2 hours |

### What This Alert Means

CRC (Cyclic Redundancy Check) errors on the SATA/SAS interface between the disk and the controller. Unlike most SMART errors, CRC errors are almost always caused by the cable or controller, NOT the disk itself. The disk data is almost certainly fine, but the connection is unreliable.

### Diagnostic Steps

1. Identify the disk with CRC errors:
   ```bash
   ssh admin@10.0.10.80
   for disk in /dev/sd*; do
     val=$(smartctl -A $disk | awk '/UDMA_CRC_Error_Count/{print $10}')
     [ -n "$val" ] && [ "$val" -gt "0" ] && echo "$disk: CRC_Errors=$val"
   done
   ```

2. Check if the errors are increasing over time (compare to Prometheus history).

3. Check for associated dmesg errors:
   ```bash
   dmesg | grep -i "ata\|sata\|error\|exception\|CRC\|reset" | grep "sdX" | tail -20
   ```

4. Physical investigation — check the SATA cable:
   - Reseat the SATA data cable on both the disk and motherboard/HBA ends
   - Try a different SATA cable (most common fix)
   - Try a different SATA port on the HBA/motherboard

5. Clear error counters and monitor after cable swap:
   ```bash
   # Note: CRC errors don't clear easily on most drives — monitor rate of increase
   # before and after cable swap
   smartctl -A /dev/sdX | grep "UDMA_CRC_Error_Count"
   ```

6. Check ZFS for any read errors caused by CRC errors:
   ```bash
   zpool status -v | grep "sdX"
   zpool clear <pool>  # if no ongoing pool issues
   zpool scrub core && zpool scrub archive && zpool scrub tera  # verify data integrity
   ```

### Decision Table

| Condition | Action |
|-----------|--------|
| Errors stop after cable reseat | Was cable issue; monitor |
| Errors continue on same port | Try different SATA port on HBA |
| Errors continue regardless of cable/port | HBA may be failing; check other disks on same HBA port |
| ZFS shows checksum errors | See [ZFSPoolChecksumErrors](#zpoolpoolchecksumerrors) |

### Verify Recovery

```bash
ssh admin@10.0.10.80
# Monitor CRC count hourly after cable swap:
smartctl -A /dev/sdX | grep "UDMA_CRC_Error_Count"
# Count should stop increasing
dmesg | grep -i "ata\|error" | grep "sdX" | tail -10
# No new ATA errors in dmesg
```

---

## SmartctlExporterDown

| Field | Value |
|-------|-------|
| Severity | Warning |
| Threshold | `smartctl_exporter` Prometheus target `up == 0` for > 5 minutes |
| First Response | 30 minutes |

### What This Alert Means

The `smartctl_exporter` process on TrueNAS (10.0.10.80) is not responding to Prometheus scrapes. All disk SMART metrics (temperature, reallocated sectors, pending sectors, CRC errors, etc.) are blind. Disk failures will not be detected until they cause visible ZFS pool problems.

### Diagnostic Steps

1. Verify the exporter is reachable from the RPi:
   ```bash
   ssh kagiso@10.0.10.10
   curl -s --connect-timeout 5 http://10.0.10.80:9633/metrics | head -10
   # 9633 is the default smartctl_exporter port — adjust if different
   ```

2. SSH to TrueNAS and check the exporter process:
   ```bash
   ssh admin@10.0.10.80
   ps aux | grep smartctl_exporter
   systemctl status smartctl_exporter 2>/dev/null
   ```

3. Check if the exporter is installed:
   ```bash
   which smartctl_exporter 2>/dev/null || ls /usr/local/bin/smartctl_exporter
   ```

4. Check the exporter logs:
   ```bash
   journalctl -u smartctl_exporter --since "1 hour ago" --no-pager 2>/dev/null
   ```

5. Verify that smartctl itself is working (exporter depends on it):
   ```bash
   smartctl -a /dev/sda | head -20
   # If smartctl fails, the exporter will also fail
   ```

6. Restart the exporter:
   ```bash
   systemctl restart smartctl_exporter
   systemctl status smartctl_exporter
   ```

7. If running as a Docker container on TrueNAS (some setups):
   ```bash
   docker ps | grep smartctl
   docker restart smartctl_exporter
   ```

8. Verify the port is listening:
   ```bash
   ss -tlnp | grep 9633
   ```

9. Test from TrueNAS itself:
   ```bash
   curl -s http://localhost:9633/metrics | head -5
   ```

### Decision Table

| Condition | Action |
|-----------|--------|
| Process not running | `systemctl start smartctl_exporter` |
| Process crashes immediately | Check logs; may be permission issue with `/dev/sd*` |
| Port not listening | Check exporter configuration file for correct bind address |
| TrueNAS update wiped exporter | Redeploy from GitOps or manual reinstall |
| smartctl binary missing | `apt install smartmontools` (TrueNAS SCALE is Debian-based) |

### Verify Recovery

```bash
ssh kagiso@10.0.10.10
curl -s http://10.0.10.80:9633/metrics | grep "smartctl_device_smart_healthy" | head -5
# Should return disk health metrics
# Also verify in Prometheus that the target shows UP
```
