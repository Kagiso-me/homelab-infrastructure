
# ADR-009 — Prometheus TSDB on Local Storage (not NFS)

**Status:** Accepted
**Date:** 2026-03-23
**Deciders:** Platform team

---

## Context

Prometheus is a write-heavy workload. It appends every scraped sample to a
Write-Ahead Log (WAL) on disk every few seconds — on this cluster, that is
thousands of samples per scrape cycle across all targets. The WAL must be
writable at all times; any sustained write failure causes Prometheus to stop
persisting data entirely, silently, while still reporting all targets as "up".

The original deployment stored the Prometheus TSDB on an NFS-backed PVC
(`storageClassName: nfs-truenas`, pointing to TrueNAS at `10.0.10.80`). Two
distinct NFS failure modes were discovered in production:

### Failure 1 — fcntl locking (boot-time crash)

NFS does not support POSIX `fcntl` advisory file locks. Prometheus creates a
`lock` file in its data directory on startup using `fcntl`. On NFS this fails
with:

```
lock DB directory: resource temporarily unavailable
```

Prometheus exits immediately, enters CrashLoopBackOff, and never starts.
Workaround: `--storage.tsdb.no-lockfile` flag suppresses lock file creation.

### Failure 2 — stale NFS file handle (runtime write failure)

When the NFS server (TrueNAS) has any network interruption, service restart,
or brief blip, the kernel file handles that Prometheus holds open for the WAL
become invalid. Subsequent writes fail with:

```
write to WAL: log samples: write /prometheus/wal/00000013: stale NFS file handle
```

This failure is silent from the outside: Prometheus continues running, all
scrape targets report "up" in the Targets UI, the HelmRelease shows `Ready`,
and no alert fires. But every single scrape is dropped — `up{}` itself returns
empty from the query API. Every dashboard shows "No data". The only evidence is
in the pod logs.

Recovery from a stale file handle requires restarting the Prometheus pod to
force the kubelet to unmount and remount the NFS volume, producing fresh kernel
file handles. The `--storage.tsdb.no-lockfile` workaround does not help here.

### Why NFS + Prometheus is a structural mismatch

The stale file handle failure is not a bug that can be patched — it is the
consequence of using a network filesystem for a process that holds long-lived
file handles open. Any disruption to the network path between the k3s node and
TrueNAS (DHCP lease renewal, switch reboot, NFS service restart, TrueNAS
update) can produce stale handles. In a homelab this is not rare; it is routine.

The second failure mode (silent data loss while appearing healthy) is
particularly dangerous for a monitoring system: the tool that should tell you
something is broken is itself broken, invisibly.

---

## Decision

**Prometheus TSDB uses `local-path` (k3s built-in local provisioner) instead of NFS.**

The `storageClassName` for the Prometheus `volumeClaimTemplate` is set to
`local-path`. The `--storage.tsdb.no-lockfile` workaround is removed — it is
not needed on local disk, and removing it restores the protection it was
bypassing.

Grafana and Alertmanager remain on `nfs-truenas`. They are not write-heavy:
Grafana writes only when dashboards or settings change; Alertmanager writes only
when alert state changes. Neither holds long-lived WAL file handles, so the
stale handle failure mode does not apply.

---

## Trade-offs

### What local-path gives up vs NFS

| Property | NFS (`nfs-truenas`) | Local-path |
|----------|--------------------|-----------:|
| Pod scheduling | Any node | **Pinned to one node** |
| Node failure behaviour | Pod reschedules to another node immediately | Pod stays Pending until the node returns |
| Historical data on node loss | Survives (data on TrueNAS) | Lost (data on node's disk) |
| WAL write reliability | Fails on any NFS blip | Local disk — no network dependency |
| Failure mode | Silent data loss, appears healthy | Obvious: pod Pending, dashboards empty |

### Why this trade-off is acceptable

The Prometheus pod is pinned to whichever node the PV was first bound to via
`nodeAffinity` set by the local-path provisioner. This means:

- **Node restarts (same node):** No data loss. Prometheus picks up where it
  left off as soon as the node is back.
- **Node permanent failure:** Prometheus cannot reschedule. Pod stays Pending.
  Historical data is lost when the node's disk is gone.

For this homelab, the nodes are physical ThinkCentre machines that get rebooted,
not replaced. Node permanent failure is an exceptional event, not a routine one.

More importantly: the NFS failure mode (silent data loss while appearing
healthy) is categorically worse than the local-path failure mode (obviously
broken, pod Pending). A monitoring system that lies about its own health is
worse than one that is clearly unavailable.

If node-level HA for Prometheus storage becomes a priority, the correct solution
is **Longhorn** (distributed block storage replicated across nodes). That
introduces meaningful operational complexity and is out of scope for the current
platform.

---

## Consequences

- Prometheus TSDB is reliable against any NFS disruption.
- `--storage.tsdb.no-lockfile` is removed from the HelmRelease — it served as
  a workaround for an NFS limitation that no longer applies.
- The Prometheus pod is effectively pinned to one k3s node. This is visible in
  the PV's `nodeAffinity`.
- Migrating to this storage class requires deleting the existing StatefulSet and
  PVC, as `volumeClaimTemplate` fields are immutable on StatefulSets. Historical
  data from before the migration is lost (in practice it was already gone due to
  the stale file handle failure).

## Migration procedure

Performed once when switching from `nfs-truenas` to `local-path`:

```bash
# 1. Suspend HelmRelease so Flux doesn't fight the manual deletion
flux suspend helmrelease kube-prometheus-stack -n monitoring

# 2. Delete the StatefulSet (pod terminates, PVC remains temporarily)
kubectl delete statefulset prometheus-kube-prometheus-stack-prometheus -n monitoring

# 3. Delete the stale NFS PVC
kubectl delete pvc prometheus-kube-prometheus-stack-prometheus-db-prometheus-kube-prometheus-stack-prometheus-0 -n monitoring

# 4. Resume — Flux recreates StatefulSet and PVC with local-path
flux resume helmrelease kube-prometheus-stack -n monitoring
```
