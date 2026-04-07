
# Runbook — Restore k3s from etcd Snapshot

**Scenario:** The cluster etcd database is corrupt, lost, or has diverged from a known-good state. Restore from a snapshot stored on TrueNAS NFS.

**Severity:** Critical
**RTO Estimate:** ~20 minutes (snapshot available) / ~35 minutes (if NFS must be remounted)
**Impact:** Cluster API is unavailable for the duration of the restore. Worker nodes continue running their existing pods but cannot be rescheduled.

> **Related runbooks:** [cluster-rebuild](./cluster-rebuild.md) | [restore-truenas-storage](./restore-truenas-storage.md) | [backup-restoration](./backup-restoration.md)

---

## What This Alert Means

etcd is the backing store for all Kubernetes cluster state (objects, secrets, config). Corruption or data loss in etcd makes the cluster API server inoperable. Symptoms include:

- `kubectl` commands returning `etcdserver: request timed out` or `connection refused`
- Control-plane pod `etcd-tywin` stuck in `CrashLoopBackOff`
- API server refusing connections while the OS on tywin is healthy

etcd snapshots are taken every 6 hours via a cron job on tywin and written to TrueNAS NFS at `/mnt/archive/backups/k8s/etcd/`. The restore process replaces the live etcd data directory with the snapshot contents.

---

## Quick Reference

| Item | Value |
|------|-------|
| Snapshot location (NFS) | `/mnt/archive/backups/k8s/etcd/` on TrueNAS 10.0.10.80 |
| NFS mount point on tywin | `/mnt/backups` |
| k3s etcd data dir | `/var/lib/rancher/k3s/server/db/` |
| Expected snapshot size | 30–60 MB |
| Snapshot filename pattern | `k3s-snapshot-YYYY-MM-DD_HHMMSS.db` |

---

## Step 1 — SSH to the control-plane node

All commands below run on tywin unless otherwise noted.

```bash
# From the hodor (10.0.10.10):
ssh kagiso@10.0.10.11
```

---

## Step 2 — Verify the NFS share is mounted

```bash
mountpoint /mnt/backups
# Expected output: /mnt/backups is a mountpoint
```

If the mount is missing:

```bash
sudo mount 10.0.10.80:/mnt/archive/backups/k8s /mnt/backups
mountpoint /mnt/backups     # verify again
```

If TrueNAS is unreachable, stop here and see [restore-truenas-storage](./restore-truenas-storage.md) before continuing.

---

## Step 3 — Locate and choose the target snapshot

```bash
ls -lht /mnt/backups/etcd/ | head -10
```

Expected output:

```
-rw-r--r-- 1 root root 44M Mar 15 02:00 k3s-snapshot-2026-03-15_020001.db
-rw-r--r-- 1 root root 43M Mar 14 20:00 k3s-snapshot-2026-03-14_200001.db
-rw-r--r-- 1 root root 43M Mar 14 14:00 k3s-snapshot-2026-03-14_140001.db
-rw-r--r-- 1 root root 42M Mar 14 08:00 k3s-snapshot-2026-03-14_080001.db
```

Choose the **most recent snapshot taken before the incident**. If the corruption is recent, use an older snapshot to avoid restoring the corrupt state.

Set a variable for the chosen snapshot to avoid typos:

```bash
SNAPSHOT=/mnt/backups/etcd/k3s-snapshot-2026-03-15_020001.db
ls -lh "$SNAPSHOT"   # confirm the file exists and is non-zero
```

---

## Step 4 — Stop k3s on the control-plane

```bash
sudo systemctl stop k3s
systemctl is-active k3s
# Expected: inactive
```

---

## Step 5 — Stop k3s-agent on all worker nodes

Workers must be stopped to prevent them from acting on stale data while etcd is being replaced.

```bash
# From tywin or the RPi, SSH to each worker:
ssh kagiso@10.0.10.12 "sudo systemctl stop k3s-agent"
ssh kagiso@10.0.10.13 "sudo systemctl stop k3s-agent"
```

Verify:

```bash
ssh kagiso@10.0.10.12 "systemctl is-active k3s-agent"
# Expected: inactive
ssh kagiso@10.0.10.13 "systemctl is-active k3s-agent"
# Expected: inactive
```

---

## Step 6 — Run the etcd snapshot restore

```bash
sudo k3s server \
  --cluster-reset \
  --cluster-reset-restore-path="$SNAPSHOT"
```

This command runs synchronously and exits when complete. It does **not** start the server persistently.

Expected output (last few lines):

```
INFO[0000] Starting temporary etcd to restore snapshot
INFO[0003] Etcd snapshot restored from /mnt/backups/etcd/k3s-snapshot-2026-03-15_020001.db
INFO[0003] Managed etcd cluster reset successful
```

If the command fails with `failed to restore snapshot`, check:
- The snapshot file is not zero bytes: `ls -lh "$SNAPSHOT"`
- The etcd data directory is writable: `sudo ls -la /var/lib/rancher/k3s/server/db/`
- k3s is fully stopped: `systemctl is-active k3s`

---

## Step 7 — Start k3s on the control-plane

```bash
sudo systemctl start k3s
```

Wait for the API server to become reachable:

```bash
kubectl wait --for=condition=Ready node/tywin --timeout=180s
# Expected: node/tywin condition met
```

If the wait times out, check the k3s log:

```bash
sudo journalctl -u k3s -n 50 --no-pager
```

---

## Step 8 — Restart k3s-agent on worker nodes

```bash
ssh kagiso@10.0.10.12 "sudo systemctl start k3s-agent"
ssh kagiso@10.0.10.13 "sudo systemctl start k3s-agent"
```

Wait for workers to rejoin (allow up to 2 minutes):

```bash
kubectl get nodes --watch
```

Expected — all three nodes Ready:

```
NAME     STATUS   ROLES                  AGE    VERSION
tywin    Ready    control-plane,master   210d   v1.31.4+k3s1
jaime    Ready    <none>                 210d   v1.31.4+k3s1
tyrion   Ready    <none>                 210d   v1.31.4+k3s1
```

---

## Step 9 — Trigger Flux reconciliation

Flux may have drifted while etcd was down. Force a reconciliation to catch up:

```bash
flux reconcile kustomization flux-system --with-source
flux get kustomizations --watch
```

Wait for all Kustomizations to show `Ready True`.

---

## Verify Recovery

```bash
# All nodes healthy
kubectl get nodes

# No pods stuck in error states
kubectl get pods -A | grep -Ev 'Running|Completed|Succeeded'

# Flux healthy
flux get all -A | grep -v True

# Confirm snapshot cron is still scheduled on tywin
crontab -l | grep etcd

# Manually verify backup writes are still working
sudo k3s etcd-snapshot save manual-post-restore
ls -lh /mnt/backups/etcd/ | head -3
```

Expected: the manual snapshot appears in the listing within 10 seconds.

---

## Decision Table

| Symptom | Action |
|---------|--------|
| NFS mount missing, TrueNAS reachable | `sudo mount 10.0.10.80:/mnt/archive/backups/k8s /mnt/backups` |
| NFS mount missing, TrueNAS unreachable | See [restore-truenas-storage](./restore-truenas-storage.md) |
| Snapshot file is 0 bytes | Choose an older snapshot; investigate backup cron |
| Restore exits with error | Verify k3s is fully stopped; check disk space on tywin |
| Workers do not rejoin after 5 minutes | Restart k3s-agent manually; check `/etc/hosts` for DNS |
| Flux stuck after restore | `flux reconcile kustomization flux-system --with-source` |
| Cluster state older than acceptable | Assess whether a Velero restore is needed for PVC data |

---

## Post-Restore Checklist

```
□ All nodes Ready
□ All pods Running or Completed
□ Flux Kustomizations all Ready
□ etcd backup cron still active (crontab -l)
□ Manual snapshot test written to /mnt/backups/etcd/
□ Incident note written: which snapshot used, data loss window
```
