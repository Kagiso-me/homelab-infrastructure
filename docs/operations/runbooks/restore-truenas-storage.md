
# Runbook — Recover from TrueNAS Hardware Failure

**Scenario:** The HP MicroServer Gen8 running TrueNAS SCALE has failed at the hardware level. This runbook covers replacing the hardware, reinstalling TrueNAS SCALE, importing the ZFS pools (`core`, `archive`, `tera`), restoring NFS exports, and verifying Kubernetes storage is functional again.

**Severity:** Critical
**RTO Estimate:** ~60–90 minutes (hardware swap + pool import) / ~120+ minutes (if data must be restored from B2)
**Impact:** All Kubernetes PVCs backed by NFS are unavailable. etcd backups are not being written. Velero cannot access its MinIO bucket. Any stateful workloads will be down until NFS is restored.

> **Related runbooks:** [restore-etcd](./restore-etcd.md) | [restore-zfs-snapshot](./restore-zfs-snapshot.md) | [restore-from-b2](./restore-from-b2.md) | [cluster-rebuild](./cluster-rebuild.md)

---

## What This Alert Means

TrueNAS SCALE at 10.0.10.80 hosts three ZFS pools which provide:
- NFS share for etcd snapshots (`/mnt/archive/backups/k8s/etcd/`)
- MinIO object storage for Velero (`http://10.0.10.80:9000`, bucket: `velero-backups`)
- NFS share for Kubernetes PV data (`/mnt/archive/appdata/`, `/mnt/tera/`)

ZFS stores all data and metadata on the **drives**, not the OS disk. If only the OS boot device or motherboard fails (not the data drives), all data pools can be imported intact onto a replacement system. The drives themselves are the backup.

---

## Quick Reference

| Item | Value |
|------|-------|
| TrueNAS host | 10.0.10.80 |
| Hardware | HP MicroServer Gen8 |
| ZFS pools | `core` (2×480GB SSD mirror), `archive` (2×4TB HDD mirror), `tera` (1×8TB HDD) |
| Data drives | All drives except the OS boot device (128GB 2.5" SSD) |
| TrueNAS SCALE ISO | https://www.truenas.com/download-truenas-scale/ |
| OS boot device | Dedicated 128GB 2.5" SSD (not part of any data pool) |
| NFS exports to restore | `/mnt/archive/backups/k8s`, `/mnt/archive/appdata`, `/mnt/tera` |
| MinIO port | 9000 |

---

## Phase 1 — Hardware Replacement

### Step 1.1 — Identify the failed component

Before replacing hardware, determine what failed:

| Symptom | Likely cause |
|---------|-------------|
| TrueNAS web UI unreachable, no ping to 10.0.10.80 | Motherboard/PSU failure or network |
| Web UI loads but pool status is DEGRADED | Drive failure — ZFS degraded, do not power cycle again until assessed |
| Web UI loads, pool ONLINE, services down | Software issue — restart services via UI before replacing hardware |

If only a drive has failed (DEGRADED pool), do **not** follow this runbook. Use the TrueNAS UI to replace the drive and resilver. This runbook is for full hardware replacement only.

### Step 1.2 — Power off and move data drives

1. Power off the MicroServer.
2. Document or photograph which drives are in which bays.
3. Remove all data drives (the data drives (core/archive/tera pools)). Leave the OS boot device if it will be reused.
4. Install drives in the replacement Gen8 chassis, maintaining the same bay order where possible (not strictly required by ZFS, but reduces confusion).

---

## Phase 2 — TrueNAS SCALE Reinstall

### Step 2.1 — Install TrueNAS SCALE on the replacement system

1. Download the latest TrueNAS SCALE ISO from https://www.truenas.com/download-truenas-scale/
2. Flash to a USB drive:
   ```bash
   # On any Linux/Mac machine:
   sudo dd if=TrueNAS-SCALE-*.iso of=/dev/sdX bs=4M status=progress
   ```
3. Boot the Gen8 from the USB installer.
4. Install TrueNAS SCALE to the **OS boot device only** — do not touch the data drives during installation.
5. Complete the installer; set the root/admin password and note it.

### Step 2.2 — Assign the static IP

After first boot, access the TrueNAS console (physical or via IPMI/iLO on Gen8):

```
Network → Interfaces → Edit the primary NIC
  IP Address: 10.0.10.80/24
  Gateway:    10.0.10.1
  DNS:        10.0.10.1
```

Verify connectivity from the RPi:

```bash
ping 10.0.10.80
ssh root@10.0.10.80
```

---

## Phase 3 — Import the ZFS Pool

### Step 3.1 — Check that ZFS can see the drives

```bash
# SSH to TrueNAS:
ssh root@10.0.10.80

# List drives available for import:
zpool import
```

Expected output — the pools should appear as importable:

```
   pool: core   (also: archive, tera)
     id: 12345678901234567890
  state: ONLINE
 action: The pool can be imported using its name or numeric identifier.
 config:
        core        ONLINE
          mirror-0  ONLINE
            sda     ONLINE
            sdb     ONLINE
```

If the pool does not appear, check that all drives are physically connected and powered. Run `lsblk` to confirm drives are visible to the OS.

### Step 3.2 — Import the pool

```bash
zpool import core && zpool import archive && zpool import tera
```

If the system reports the pool was last used by a different host and requires `-f`:

```bash
zpool import -f core && zpool import -f archive && zpool import -f tera
```

Verify the pool is online:

```bash
zpool status
```

Expected output:

```
  pool: core   (and archive, tera)
 state: ONLINE
  scan: scrub repaired 0B in 00:12:34 with 0 errors
config:
        NAME        STATE     READ WRITE CKSUM
        core        ONLINE       0     0     0
          mirror-0  ONLINE       0     0     0
            sda     ONLINE       0     0     0
            sdb     ONLINE       0     0     0
```

Verify data is accessible:

```bash
ls /mnt/archive/
# Expected: backups  (or similar dataset directories)  (or similar dataset directories)

ls /mnt/archive/backups/k8s/etcd/ | tail -5
# Expected: recent snapshot .db files
```

---

## Phase 4 — Restore NFS Exports

TrueNAS stores NFS share configuration in its database, which is on the OS boot device. After a fresh install, NFS shares must be re-created.

### Step 4.1 — Via TrueNAS Web UI (preferred)

Navigate to `http://10.0.10.80` → **Shares → NFS → Add**:

| Share path | Allowed hosts | Map root user | Notes |
|------------|---------------|---------------|-------|
| `/mnt/archive/backups/k8s` | `10.0.10.0/24` | Root to root | etcd snapshots, Velero MinIO |
| `/mnt/archive/appdata` | `10.0.10.0/24` | Root to root | Kubernetes PV application data |
| `/mnt/tera` | `10.0.10.0/24` | Root to root | Media library |

Enable the NFS service: **System → Services → NFS → Start**.

### Step 4.2 — Via CLI (alternative)

```bash
# SSH to TrueNAS
ssh root@10.0.10.80

# Start the NFS service
systemctl start nfs-kernel-server

# Manually add exports (temporary, until UI re-creates them):
cat >> /etc/exports <<'EOF'
/mnt/archive/backups/k8s  10.0.10.0/24(rw,sync,no_subtree_check,no_root_squash)
/mnt/archive/appdata      10.0.10.0/24(rw,sync,no_subtree_check,no_root_squash)
/mnt/tera        10.0.10.0/24(rw,sync,no_subtree_check,no_root_squash)
EOF

exportfs -ra
showmount -e 10.0.10.80
```

Expected output from `showmount`:

```
Export list for 10.0.10.80:
/mnt/archive/backups/k8s  10.0.10.0/24
/mnt/archive/appdata      10.0.10.0/24
/mnt/tera        10.0.10.0/24
```

---

## Phase 5 — Restore MinIO for Velero

MinIO is deployed as a TrueNAS app or a Docker container at port 9000. Re-deploy it pointing at the existing data directory.

```bash
# Verify MinIO data directory exists on the restored pool:
ls /mnt/archive/minio/velero-backups/
```

Re-deploy via TrueNAS web UI: **Apps → Available Applications → minio** → configure with:
- Data directory: `/mnt/archive/minio`
- Port: 9000 / 9001
- Access key and secret: retrieve from password manager (same values as before)

Test MinIO is reachable from the cluster:

```bash
# From tywin (10.0.10.11):
curl -I http://10.0.10.80:9000/minio/health/live
# Expected: HTTP/1.1 200 OK
```

---

## Phase 6 — Verify Kubernetes PVC Mounts

### Step 6.1 — Remount NFS on tywin (control-plane)

The NFS mount in `/etc/fstab` on tywin should reconnect automatically once TrueNAS is back at 10.0.10.80:

```bash
ssh kagiso@10.0.10.11
sudo mount -a
mountpoint /mnt/backups
# Expected: /mnt/backups is a mountpoint

ls /mnt/backups/etcd/ | tail -3
# Expected: recent snapshot files
```

### Step 6.2 — Check Kubernetes PVCs

```bash
kubectl get pvc -A
```

All PVCs should transition back to `Bound` within a few minutes of NFS becoming available.

If PVCs remain `Lost` or `Pending`:

```bash
kubectl describe pvc <pvc-name> -n <namespace>
# Look for: "failed to ensure volume ... connection refused" or "nfs: mount failed"
```

Restart the NFS client pods to force remounting:

```bash
kubectl rollout restart deployment/<app-name> -n <namespace>
```

### Step 6.3 — Verify Velero backup storage location

```bash
velero backup-location get
# Expected: STATUS = Available

velero backup get
# Expected: recent backups listed
```

---

## Verify Recovery

```bash
# TrueNAS pool healthy
ssh root@10.0.10.80 "zpool status"

# NFS exports active
showmount -e 10.0.10.80

# tywin NFS mount working
ssh kagiso@10.0.10.11 "mountpoint /mnt/backups && ls /mnt/backups/etcd/ | tail -3"

# All Kubernetes PVCs bound
kubectl get pvc -A | grep -v Bound

# Velero storage accessible
velero backup-location get

# Test etcd snapshot write
ssh kagiso@10.0.10.11 "sudo k3s etcd-snapshot save manual-truenas-restore-test"
ssh kagiso@10.0.10.11 "ls -lh /mnt/backups/etcd/ | tail -3"

# All pods recovered
kubectl get pods -A | grep -Ev 'Running|Completed|Succeeded'
```

---

## Post-Recovery Checklist

```
□ zpool status shows ONLINE, 0 errors
□ All NFS shares visible in showmount -e 10.0.10.80
□ /mnt/backups mountpoint active on tywin
□ All PVCs in Bound state
□ Velero backup-location STATUS = Available
□ Manual etcd snapshot written successfully
□ TrueNAS UI accessible at http://10.0.10.80
□ B2 sync job reconfigured and scheduled in TrueNAS
□ Snapshot schedules recreated in TrueNAS (Datasets → Snapshots)
□ Grafana shows TrueNAS disk metrics
□ Incident log entry written with: cause, duration, data loss window
```

---

## Decision Table

| Situation | Action |
|-----------|--------|
| Pool appears DEGRADED after import | Assess failed drives before importing; `zpool status` for detail |
| `zpool import` shows pool not found | Verify drives are connected; run `lsblk` to check visibility |
| `zpool import` requires `-f` | Safe to use if drives were cleanly shut down; risky if sudden failure |
| NFS clients (k8s nodes) cannot mount | Check firewall on TrueNAS; `ufw status` or TrueNAS firewall settings |
| PVCs remain Lost after NFS restored | Restart affected deployments; check PV/PVC binding with `kubectl describe` |
| MinIO data directory missing | Pool data may be on B2 — see [restore-from-b2](./restore-from-b2.md) |
| Hardware replacement not same model | ZFS is hardware-agnostic; pool import works on any compatible system |
| No hardware available immediately | Run NFS from RPi temporarily; update PV server address in manifests |
