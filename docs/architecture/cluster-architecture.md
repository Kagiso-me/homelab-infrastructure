# Cluster Architecture

## Node Topology

The cluster comprises three physical nodes running k3s. All nodes are on the same Layer-2 subnet (`10.0.10.0/24`), which is a prerequisite for MetalLB ARP mode.

| Name | IP Address | Role | Notes |
|---|---|---|---|
| `tywin` | 10.0.10.11 | Control-plane | Runs k3s server; hosts etcd, API server, controller-manager, scheduler |
| `jaime` | 10.0.10.12 | Worker | Runs k3s agent; schedules workload pods |
| `tyrion` | 10.0.10.13 | Worker | Runs k3s agent; schedules workload pods |

> Resource sizing per node is detailed in the [Resource Sizing](#resource-sizing) section below.

---

## k3s Configuration Highlights

k3s is deployed with several non-default flags to integrate cleanly with the platform's chosen components.

| Flag / Option | Value | Reason |
|---|---|---|
| `--disable traefik` | `true` | Traefik is installed separately via FluxCD HelmRelease with a pinned chart version and custom values. The bundled k3s Traefik cannot be version-pinned or fully customised via GitOps. |
| `--disable servicelb` | `true` | MetalLB is used as the bare-metal LoadBalancer. The bundled ServiceLB (klipper-lb) conflicts with MetalLB's ARP announcements. |
| `--cluster-init` | `true` (on `tywin`) | Enables embedded etcd on the control-plane node instead of the default SQLite backend, providing a more production-representative data store and enabling snapshot/restore operations. |
| `--node-taint` | None applied to CP | The control-plane is allowed to schedule workloads. Given the single-CP constraint, isolating it would reduce overall cluster capacity with no HA benefit. |
| Embedded etcd snapshots | Every 6 hours, retained for 5 | etcd snapshots are written to the local NFS mount as a fast-recovery path before Velero backup runs. |

---

## Network Topology

```
Internet
    |
    | (HTTP/HTTPS)
    v
+----------------------------+
|  Router / Firewall         |  Port-forwards :80, :443 -> 10.0.10.110
+----------------------------+
    |
    v
+--------------------------------------------+   10.0.10.0/24
|  Node Subnet                               |
|                                            |
|  10.0.10.11  tywin   (control-plane)      |
|  10.0.10.12  jaime   (worker)             |
|  10.0.10.13  tyrion  (worker)             |
|                                            |
|  MetalLB pool:  10.0.10.110 - 10.0.10.125 |
|  Traefik VIP:   10.0.10.110               |
+--------------------------------------------+
    |
    | (NFS, iSCSI)
    v
+--------------------------------------------+   10.0.10.0/24
|  Storage Subnet                            |
|                                            |
|  10.0.10.80   TrueNAS SCALE                |
|              NFS export: /mnt/core/k8s-volumes
+--------------------------------------------+
```

**Key network facts:**

- All cluster nodes are on `10.0.10.0/24`. MetalLB operates in ARP (Layer-2) mode and requires all nodes and the LoadBalancer IP pool to share a broadcast domain.
- Traefik is pinned to `10.0.10.110` via a MetalLB `IPAddressPool` annotation on its Service. This IP is referenced in DNS and router port-forward rules and must not change.
- TrueNAS is on a separate management subnet (`10.0.10.0/24`) reachable from all nodes. NFS traffic is not encrypted at the network layer; network isolation is relied upon for NFS security.
- The MetalLB pool `10.0.10.110–10.0.10.125` is reserved in the router's DHCP server (excluded from dynamic assignment).

---

## Control-Plane High Availability

### Design Choice: Single Control-Plane

This cluster intentionally runs a **single control-plane node** (`tywin`). This is a documented trade-off captured in [ADR-005](decisions/ADR-005-single-control-plane.md).

| Property | Detail |
|---|---|
| Control-plane nodes | 1 (`tywin`) |
| etcd quorum | Not applicable — single member, no quorum voting |
| Failure domain | Loss of `tywin` = full cluster outage. Workers lose API connectivity and cannot schedule new pods. Running pods continue until they terminate or are evicted, but no new scheduling occurs. |
| Recovery path | Restore etcd snapshot to a freshly provisioned node; re-join workers. See [`cluster-rebuild.md`](../operations/runbooks/cluster-rebuild.md). |
| Accepted risk | Documented and accepted per ADR-005. RTO target: 60–90 minutes from snapshot restore. |

### Why Not Multi-Master?

Three-node etcd HA requires either three nodes with equivalent roles (removing the worker capacity benefit) or a dedicated etcd VM (additional hardware cost). For a homelab with a rebuild target of under 2 hours and nightly offsite backups, the operational complexity of HA etcd outweighs the availability benefit. See ADR-005 for the full rationale.

---

## Upgrade Strategy

Node and k3s upgrades are managed by **system-upgrade-controller**, deployed via FluxCD. Upgrades are applied via `Plan` custom resources that reference a target k3s version.

### Upgrade Order

```
1. Workers upgraded first (jaime, tyrion) — rolling, one at a time
      |
      v
2. Control-plane upgraded last (tywin)
```

Upgrading workers first ensures that if a k3s version causes a regression, the control-plane remains stable and the cluster is recoverable without an etcd restore.

### Upgrade Procedure (Summary)

1. Update the k3s version tag in the `Plan` manifest in Git.
2. FluxCD reconciles the change; system-upgrade-controller cordons and drains each worker node in sequence, applies the upgrade, then uncordons.
3. After workers are healthy, the control-plane `Plan` triggers. The node drains, upgrades, and rejoins.
4. Verify node versions with `kubectl get nodes` and review Prometheus alerts for post-upgrade anomalies.

> Full upgrade runbook: [`docs/operations/runbooks/k3s-upgrade.md`](../operations/runbooks/k3s-upgrade.md)

---

## Resource Sizing

All three k3s nodes are **Lenovo ThinkCentre M93p** small form-factor machines — identical hardware makes for predictable behaviour and simplified maintenance.

| Node | CPU | RAM | Storage | Role |
|---|---|---|---|---|
| `tywin` | Intel Core i5-4570T (4c/4t @ 2.9GHz, 35W TDP) | 16 GB DDR3 | 256 GB SSD | Control-plane + etcd + some workloads |
| `jaime` | Intel Core i5-4570T (4c/4t @ 2.9GHz, 35W TDP) | 16 GB DDR3 | 256 GB SSD | General workloads |
| `tyrion` | Intel Core i5-4570T (4c/4t @ 2.9GHz, 35W TDP) | 16 GB DDR3 | 256 GB SSD | General workloads + observability stack |

> **Planned CPU upgrade:** All three nodes will be upgraded to Intel Core i7-4790T (4c/8t @ 2.7GHz base / 3.9GHz turbo, 45W TDP) when parts arrive, doubling thread count. No cluster changes required — nodes are drained, upgraded, and rejoined one at a time.

**Persistent storage** is provided entirely by TrueNAS via NFS. No node-local PersistentVolumes are used in steady state, which means pods can reschedule freely across workers without data affinity constraints.
