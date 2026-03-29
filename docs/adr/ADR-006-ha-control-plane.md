# ADR-006: HA Control-Plane (3-Node etcd Cluster)

| Field | Value |
|---|---|
| **Date** | 2026-03-29 |
| **Status** | Accepted |
| **Supersedes** | [ADR-005](ADR-005-single-control-plane.md) |
| **Deciders** | Platform owner |

---

## Context

[ADR-005](ADR-005-single-control-plane.md) established a single control-plane node (`tywin`) on the grounds that a 3-node etcd cluster would either eliminate dedicated worker capacity or require additional hardware.

That reasoning was re-evaluated against the specific hardware available: three identical Lenovo ThinkCentre M93p nodes, each with **16 GB RAM**. The key insight is that k3s server (control-plane) overhead is approximately 1–2 GB per node. On 16 GB nodes, this leaves ~14 GB per node for workload scheduling — a modest cost for a significant availability improvement.

The original ADR assumed that combining control-plane and worker roles on a 16 GB node would create resource pressure. In practice, at homelab workload scale (20–30 pods of lightweight services), this pressure does not materialise. The concern is valid for clusters with bursty or memory-intensive workloads, but does not apply here.

---

## Decision

Convert all three nodes (`tywin`, `jaime`, `tyrion`) to **k3s server nodes**, each running:
- etcd (embedded, 3-member cluster)
- API server
- controller-manager
- scheduler
- kubelet (schedules and runs workload pods)

`tywin` initialises the cluster with `--cluster-init`. `jaime` and `tyrion` join with `--server https://10.0.10.100:6443`.

No node is tainted. All three nodes are schedulable for workloads. No dedicated worker nodes remain.

---

## Consequences

### Positive

- **HA control-plane.** The cluster tolerates the loss of any single node. etcd maintains quorum with 2 of 3 members. The API server remains available on the surviving nodes.
- **Higher total schedulable capacity.** Three nodes contribute ~14 GB each (~42 GB total) versus the previous ~32 GB from two workers.
- **Simpler recovery.** A failed node is replaced by provisioning a new machine and joining it as an additional server. No need to restore from an etcd snapshot for single-node failures.
- **Uniform node role.** All nodes are identical in role and configuration. No asymmetry between control-plane and worker lifecycle.

### Negative

- **etcd runs alongside workloads.** On all three nodes, etcd shares CPU and memory with workload pods. At 16 GB per node, this is acceptable; it becomes a concern if workloads grow significantly more memory-intensive.
- **Shared stateful services remain a bottleneck.** The HA control-plane removes the API single point of failure, but PostgreSQL, Redis, and some observability paths still run as single instances and can degrade workloads during a node loss.
- **Upgrade complexity is marginally higher.** All three nodes are upgraded by a single `Plan` (rolling, one at a time). Previously, workers were upgraded before the control-plane. The ordering distinction is no longer meaningful; `concurrency: 1` preserves quorum throughout.

---

## Alternatives Considered

### Dedicated Control-Plane + 2 CP+Workers (Option B)

Run `tywin` as a dedicated control-plane (no workloads), `jaime` and `tyrion` as control-plane + workers.

**Why rejected:**

- Provides identical HA guarantees to Option C.
- Wastes ~14 GB of schedulable RAM on `tywin` for no meaningful benefit at 16 GB per node.
- The argument for isolating etcd from workload pressure is valid when nodes have 8 GB or less, not at 16 GB with homelab-scale workloads.

### Single Control-Plane (ADR-005)

**Why superseded:**

- No HA. Loss of `tywin` = full cluster outage.
- RTO of 60–90 minutes is acceptable but unnecessary given the hardware available.
- The resource trade-off that justified the original decision does not hold at 16 GB per node.

---

## API Server High Availability Note

The control-plane is exposed through **kube-vip** on `10.0.10.100`. kubeconfig, Flux, and CI
should target this VIP rather than an individual server node IP.

---

## Mitigation

| Mitigation | Detail |
|---|---|
| **etcd snapshots every 6 hours** | All server nodes are configured with S3 snapshot settings. Snapshots stored in MinIO on TrueNAS. |
| **Nightly Velero backups to MinIO** | Application state backed up independently of etcd. |
| **Nightly offsite copy to Backblaze B2** | Protects against NAS failure or site-level loss. |
| **Documented recovery runbook** | [`docs/operations/runbooks/cluster-rebuild.md`](../../operations/runbooks/cluster-rebuild.md) |
| **resource requests/limits on workloads** | Prevents workloads from consuming memory that would pressure etcd. Enforced per-deployment. |

