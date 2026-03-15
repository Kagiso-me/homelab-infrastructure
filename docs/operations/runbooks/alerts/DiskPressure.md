
# Alert Runbook — DiskPressure

**Alert:** `NodeDiskPressure` or `PVCDiskUsageHigh`
**Threshold:** Node disk > 80%, or PVC > 85% capacity
**Severity:** Warning at 80%, Critical at 90%
**First response time:** 30 minutes

---

## What This Alert Means

**Node disk pressure:** The node's local filesystem is filling up. Kubernetes will begin evicting pods when this condition is detected. The node condition `DiskPressure=True` will appear and no new pods will be scheduled on the node.

**PVC disk usage high:** A persistent volume claim is approaching its declared capacity. NFS volumes do not enforce hard limits, but tracking usage against declared size is important for planning.

---

## Step 1 — Identify the source

```bash
# Check node conditions
kubectl describe node <node-name> | grep -A10 Conditions

# Check PVC usage
kubectl get pvc -A
```

For node disk pressure, SSH to the node:

```bash
df -h
du -sh /var/lib/rancher/k3s/* 2>/dev/null | sort -rh | head -10
```

---

## Step 2 — Common sources of node disk consumption

| Directory | Contents | Action |
|-----------|----------|--------|
| `/var/lib/rancher/k3s/` | k3s data, container images, local PVs | Prune unused images |
| `/var/log/` | System and container logs | Truncate old logs |
| `/var/lib/rancher/k3s/storage/` | local-path-provisioner volumes | Check PVC usage |

---

## Step 3 — Free node disk space

**Prune unused container images:**

```bash
# SSH to the affected node
sudo k3s crictl images | grep -v REPOSITORY
sudo k3s crictl rmi --prune
```

**Clean old k3s etcd snapshots on the control-plane:**

```bash
ls -lht /mnt/backups/etcd/
# Remove snapshots beyond retention policy manually if cron failed to clean up
find /mnt/backups/etcd/ -name "k3s-snapshot-*.db" -mtime +7 -delete
```

**Truncate large log files:**

```bash
# Find large log files
find /var/log -name "*.log" -size +100M
# Truncate (do not delete — deleting may not free space if a process has the file open)
sudo truncate -s 0 /var/log/<large-file>.log
```

---

## Step 4 — Expand a PVC that is too small

For NFS-backed PVCs, expansion is online and immediate:

```bash
kubectl edit pvc <pvc-name> -n <namespace>
```

Change `storage: 10Gi` to `storage: 20Gi` (or appropriate size).

Verify:

```bash
kubectl get pvc <pvc-name> -n <namespace>
```

The NFS provisioner does not enforce hard limits at the filesystem level. The declared size is advisory. However, always keep declared sizes reasonably accurate for capacity planning.

---

## Step 5 — For Prometheus specifically

Prometheus stores time-series data in `/prometheus/` (on the PVC). If this is growing faster than expected:

```bash
kubectl exec -n monitoring prometheus-0 -- df -h /prometheus/
```

Reduce retention in the HelmRelease values:

```yaml
prometheus:
  prometheusSpec:
    retention: 7d          # default is 10d
    retentionSize: "15GB"  # hard size cap
```

Commit the change to Git. Flux applies it. Prometheus will automatically delete old data to stay within limits.

---

## Step 6 — Verify recovery

```bash
kubectl describe node <node-name> | grep DiskPressure
# Should show: DiskPressure=False
```

```bash
df -h   # on the affected node
```

Disk usage should be below 80%.

---

## Long-term Actions

- Review PVC sizing quarterly and adjust declarations before they fill.
- Configure TrueNAS dataset quotas per dataset to get early warnings at the storage level.
- Add a node disk usage alert that fires before Kubernetes DiskPressure triggers (which has its own eviction logic that may disrupt workloads).
