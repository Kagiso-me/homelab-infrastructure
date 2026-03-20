# ADR-005: Single Control-Plane Node

| Field | Value |
|---|---|
| **Date** | 2026-03-14 |
| **Status** | Accepted |
| **Deciders** | Platform owner |

---

## Context

The cluster consists of three physical nodes: `tywin` (10.0.10.11), `jaime` (10.0.10.12), and `tyrion` (10.0.10.13). These are consumer or small-form-factor machines acquired for homelab use.

A highly-available Kubernetes control-plane — specifically a highly-available etcd cluster — requires an **odd number of voting members** (minimum 3) to tolerate the loss of at least one member while maintaining quorum. The standard configurations are:

- **3-node etcd cluster:** All three nodes run control-plane components. This consumes the entire cluster for control-plane overhead and leaves no dedicated worker capacity without additional hardware.
- **5-node etcd cluster:** Provides tolerance for 2 simultaneous failures; clearly out of scope for a 3-node homelab.
- **External etcd with 3 dedicated VMs:** Separates etcd from the k3s server nodes; adds significant operational complexity and requires additional compute.

The homelab has a fixed hardware budget (3 nodes). Acquiring a fourth node solely to dedicate as an etcd member, or converting all three existing nodes to control-plane-only roles, would either require hardware spend or eliminate all dedicated worker capacity.

The operational objective for this platform is a **rebuild time under 2 hours** using documented runbooks, etcd snapshots, and Velero backups — not continuous availability.

---

## Decision

Run a **single control-plane node** (`tywin`, 10.0.10.11) with embedded etcd. The two remaining nodes (`jaime`, `tyrion`) run as workers only.

k3s is started on `tywin` with `--cluster-init` to enable the embedded etcd backend (as opposed to the default SQLite), which supports snapshot and restore operations compatible with standard etcd tooling.

`jaime` and `tyrion` join the cluster as agents (workers) and do not participate in etcd.

---

## Consequences

### Positive

- **Simpler operations.** A single control-plane means there is no etcd quorum to manage, no leader-election complexity to reason about, and no risk of split-brain scenarios.
- **Lower resource overhead.** Control-plane components (API server, controller-manager, scheduler, etcd) run on one node only. Workers dedicate their full capacity to workloads and observability stack.
- **Faster upgrades.** Upgrading a single control-plane is a simpler operation than a rolling multi-master upgrade. system-upgrade-controller handles it in one step after workers are upgraded.
- **Easier mental model.** For a single operator, a single-CP cluster is straightforward to reason about, debug, and document.

### Negative

- **Control-plane failure = full cluster outage.** If `tywin` becomes unavailable (hardware failure, OS panic, accidental misconfiguration), the Kubernetes API server is unreachable. Workers retain existing pod state temporarily but cannot schedule new pods, process ConfigMap/Secret updates, or respond to health-check failures.
- **etcd cannot form quorum after node failure.** A single-member etcd instance has no quorum concept — it is either available or it is not. There is no automatic failover. Recovery requires restoring from a snapshot onto a replacement node.
- **Recovery requires manual intervention.** Unlike a 3-node HA cluster that can self-heal a single node failure, recovery from control-plane loss is a deliberate, operator-driven process.
- **RTO is measured in tens of minutes to over an hour.** The estimated recovery time objective is **60–90 minutes** from the moment a snapshot restore begins on a freshly provisioned node. This is incompatible with production SLAs but acceptable for a personal homelab.

---

## Alternatives Considered

### 3-Node etcd Cluster (All Nodes as Control-Plane)

Run `--cluster-init` on `tywin` and add `jaime` and `tyrion` as additional server nodes, forming a 3-member etcd cluster.

**Why rejected:**

- k3s server nodes running etcd, API server, controller-manager, and scheduler have materially higher baseline resource consumption than agent nodes. On 16 GB RAM nodes, this significantly reduces the memory available for workloads.
- The observability stack (kube-prometheus-stack + Loki) is a large consumer of memory and CPU. Running it alongside full control-plane components on all three nodes creates resource pressure with no headroom.
- Worker node failure in a 3-node etcd cluster still requires careful management to avoid losing quorum. Losing 2 of 3 nodes simultaneously would still be unrecoverable without a snapshot restore.
- The operational complexity increase (leader elections, etcd health monitoring across 3 nodes, more complex upgrade sequencing) does not justify the availability improvement for a homelab with a < 2h rebuild target.

### Dedicated etcd VM (External etcd)

Provision a lightweight VM (or three, for quorum) to run etcd external to the k3s nodes.

**Why rejected:**

- Requires additional hardware or a hypervisor host, neither of which is currently available in the homelab.
- Adds a new class of infrastructure (VMs) with its own lifecycle, networking, and backup requirements.
- Disproportionate to the scale and purpose of the platform.

---

## Mitigation

The consequences of single-CP failure are accepted and mitigated by the following measures:

| Mitigation | Detail |
|---|---|
| **etcd snapshots every 6 hours** | k3s embedded etcd is configured to snapshot every 6 hours. Snapshots are retained for 5 generations. Snapshots are stored on the NFS mount (`10.0.10.80:/mnt/core/k8s-volumes`) so they survive node failure. |
| **Nightly Velero backups to MinIO** | Velero runs a nightly backup of all cluster resources and PVC data to MinIO on TrueNAS. This captures application state beyond what etcd holds. |
| **Nightly offsite copy to Backblaze B2** | MinIO bucket contents (including Velero backups) are synced to Backblaze B2 nightly. This protects against NAS failure or site-level loss. |
| **Documented recovery runbook** | A step-by-step control-plane recovery procedure is maintained at [`docs/operations/runbooks/cluster-rebuild.md`](../../operations/runbooks/cluster-rebuild.md). The runbook is tested at least once per quarter or after any major platform change. |
| **Rebuild target < 2 hours** | All platform configuration is in Git. With a working etcd snapshot (or Velero restore), a new `tywin` can be provisioned and FluxCD reconciled within the target window. |
| **Watchdog heartbeat** | Alertmanager sends a continuous heartbeat to `watchdog-webhook`. Silence of this heartbeat signals total cluster loss to an external monitoring endpoint, providing detection independent of the cluster itself. |

---

## Review

This decision should be revisited if:

- A fourth node becomes available that could serve as a dedicated etcd member or additional control-plane node.
- Service criticality increases to the point where a 60–90 minute RTO is no longer acceptable.
- k3s introduces a simpler embedded HA mechanism that reduces the resource overhead of multi-CP configurations.
