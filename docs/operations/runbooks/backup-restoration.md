
# Runbook - Backup Restoration

**Scenario:** Recovering from data loss using etcd snapshots (cluster state) and Velero backups (persistent volumes).

> This runbook must be tested against a non-production cluster before it can be considered valid. Run a restoration test quarterly and log the result in the disaster recovery game-day record.

---

## Part A — Restore Cluster State from etcd Snapshot

**Use when:** The Kubernetes cluster state (etcd database) has been lost or corrupted. This covers scenarios like accidental `kubectl delete` of critical resources, etcd corruption, or control-plane disk failure.

### Prerequisites

- k3s installed on the HA server nodes or cluster rebuilt via Ansible
- TrueNAS NFS share mounted at `/mnt/backups`
- Snapshot file available at `/mnt/backups/etcd/`

### Step 1 — Mount the NFS share (if not already mounted)

```bash
sudo mount -a
mountpoint /mnt/backups  # must succeed
```

### Step 2 — Identify the target snapshot

```bash
ls -lht /mnt/backups/etcd/
```

Choose the most recent snapshot, or the last known-good snapshot before the incident.

```
k3s-snapshot-2026-03-14_020001.db   42M   <-- most recent
k3s-snapshot-2026-03-13_020001.db   41M
```

### Step 3 — Stop k3s on the first server node

```bash
sudo systemctl stop k3s
```

Verify stopped:

```bash
systemctl is-active k3s
# should return: inactive
```

### Step 4 — Restore the snapshot

```bash
sudo k3s server \
  --cluster-reset \
  --cluster-reset-restore-path=/mnt/backups/etcd/k3s-snapshot-YYYY-MM-DD_HHMMSS.db
```

This command will:
1. Stop etcd
2. Reset the cluster to the snapshot state
3. Exit when complete

Expected output includes: `Managed etcd cluster reset successful`

### Step 5 — Start k3s

```bash
sudo systemctl start k3s
```

Wait for the API server to become ready:

```bash
kubectl wait --for=condition=Ready node/tywin --timeout=120s
```

### Step 6 — Rejoin the remaining HA server nodes

The other server nodes lose their connection to the restored datastore during the reset. Restart `k3s` on each remaining server one at a time:

```bash
ansible-playbook -i ansible/inventory/homelab.yml ansible/playbooks/maintenance/reboot-nodes.yml --limit tyrion
ansible-playbook -i ansible/inventory/homelab.yml ansible/playbooks/maintenance/reboot-nodes.yml --limit jaime
```

Or manually on each remaining server:

```bash
sudo systemctl restart k3s
```

### Step 7 — Verify cluster state

```bash
kubectl get nodes
kubectl get pods -A
flux get kustomizations
```

All nodes should be Ready. Flux will reconcile any drift from the restored state.

---

## Part B — Restore Persistent Volume Data with Velero

**Use when:** Application data in PVCs needs to be restored (e.g., database corruption, accidental data deletion).

### Prerequisites

- Cluster running and healthy
- Velero deployed and running (`kubectl get pods -n velero`)
- Velero has access to TrueNAS backup storage location

### Step 1 — List available backups

```bash
velero backup get
```

Example output:

```
NAME                          STATUS     CREATED                         EXPIRES   STORAGE LOCATION
daily-cluster-backup-20260314   Completed  2026-03-14 03:00:00 +0000 UTC   6d        truenas-minio
daily-cluster-backup-20260313   Completed  2026-03-13 03:00:00 +0000 UTC   5d        truenas-minio
```

### Step 2 — (Optional) Restore a specific namespace only

```bash
velero restore create \
  --from-backup daily-cluster-backup-20260314 \
  --include-namespaces monitoring \
  --wait
```

### Step 3 — Full cluster restore

```bash
velero restore create \
  --from-backup daily-cluster-backup-20260314 \
  --wait
```

### Step 4 — Monitor restore progress

```bash
velero restore get
velero restore describe <restore-name> --details
```

Watch for any warnings or errors in the output. Common issues:

- **PVC already exists** — restore skips existing resources by default. Use `--existing-resource-policy=update` to overwrite.
- **Namespace already exists** — safe to ignore, the restore will create resources within it.

### Step 5 — Verify application data

For each critical application, verify data integrity after restore:

```bash
# Example: check Grafana dashboards are present
kubectl exec -n monitoring deployment/grafana -- ls /var/lib/grafana/dashboards/

# Example: check Prometheus data
kubectl exec -n monitoring prometheus-0 -- ls /prometheus/
```

---

## Restoration Test Procedure

Perform this quarterly on a spare machine or in an isolated environment.

1. Spin up a fresh Ubuntu VM or disposable host set.
2. Run the full cluster rebuild procedure.
3. Restore the most recent etcd snapshot.
4. Bootstrap Flux.
5. Restore the most recent Velero backup.
6. Verify that Grafana loads with expected dashboards.
7. Verify that at least one critical application path is running with its data intact.
8. Record the actual time taken.
9. Update the RTO documentation if actual time exceeds the target.
10. Log the outcome in [Disaster Recovery Game Day](./disaster-recovery-gameday.md).

**Document the result in a test log** with: date, snapshot used, Velero backup used, steps where issues occurred, actual time taken.

---

## Recovery Time Summary

| Scenario | Estimated Time |
|----------|---------------|
| etcd restore only | ~20 min |
| Full rebuild + etcd restore | ~45 min |
| Velero restore (single namespace) | ~10 min |
| Velero full restore | ~20 min |
| Full disaster recovery | ~60 min |
