# Cluster Architecture

## Node Topology

The cluster comprises three physical nodes running k3s. All nodes are on the same Layer-2 subnet (`10.0.10.0/24`), which is a prerequisite for MetalLB ARP mode.

| Name | IP Address | Role | Notes |
|---|---|---|---|
| `tywin` | 10.0.10.11 | Control-plane + Worker | Initialises cluster (`--cluster-init`); runs etcd, API server, controller-manager, scheduler, and workloads |
| `jaime` | 10.0.10.12 | Control-plane + Worker | Joins as additional server; runs etcd, API server, controller-manager, scheduler, and workloads |
| `tyrion` | 10.0.10.13 | Control-plane + Worker | Joins as additional server; runs etcd, API server, controller-manager, scheduler, and workloads |

> Resource sizing per node is detailed in the [Resource Sizing](#resource-sizing) section below.

---

## k3s Configuration Highlights

k3s is deployed with several non-default flags to integrate cleanly with the platform's chosen components.

| Flag / Option | Value | Reason |
|---|---|---|
| `--disable traefik` | `true` | Traefik is installed separately via FluxCD HelmRelease with a pinned chart version and custom values. The bundled k3s Traefik cannot be version-pinned or fully customised via GitOps. |
| `--disable servicelb` | `true` | MetalLB is used as the bare-metal LoadBalancer. The bundled ServiceLB (klipper-lb) conflicts with MetalLB's ARP announcements. |
| `--cluster-init` | `true` (on `tywin` only) | Bootstraps the embedded etcd cluster on the first server node. `jaime` and `tyrion` join with `--server https://tywin:6443`. |
| `--node-taint` | None applied | All three server nodes schedule workloads. With 16 GB RAM per node, tainting control-plane nodes would waste schedulable capacity for no meaningful resource isolation benefit at this scale. |
| Embedded etcd snapshots | Every 6 hours, retained for 7 | All server nodes are configured with S3 snapshot settings. The etcd leader takes snapshots; snapshots are stored in MinIO on TrueNAS and synced offsite to Backblaze B2. |

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
|  10.0.10.11  tywin   (control-plane + worker)  |
|  10.0.10.12  jaime   (control-plane + worker)  |
|  10.0.10.13  tyrion  (control-plane + worker)  |
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

### Design Choice: 3-Node HA Control-Plane

All three nodes run both control-plane and worker roles, forming a 3-member embedded etcd cluster. This is documented in [ADR-006](../adr/ADR-006-ha-control-plane.md).

| Property | Detail |
|---|---|
| Control-plane nodes | 3 (`tywin`, `jaime`, `tyrion`) |
| etcd quorum | 3-member cluster; majority quorum = 2. Tolerates loss of any 1 node. |
| Failure domain | Loss of any single node: cluster API remains available, etcd maintains quorum, workloads reschedule to remaining nodes. |
| Recovery path | Replace failed node, re-join as additional server with `--server https://10.0.10.11:6443`. |
| API server VIP | Not implemented. kubeconfig points to `tywin` (10.0.10.11). If tywin is unavailable, update kubeconfig to point to `jaime` or `tyrion` — workloads continue running regardless. |

---

## Upgrade Strategy

Node and k3s upgrades are managed by **system-upgrade-controller**, deployed via FluxCD. Upgrades are applied via `Plan` custom resources that reference a target k3s version.

### Upgrade Order

```
All 3 nodes upgraded by plan-server — rolling, one at a time (concurrency: 1)
Each node: cordon → drain → upgrade → uncordon → rejoin
```

Since all nodes are both control-plane and workers, a single `Plan` (targeting `node-role.kubernetes.io/control-plane: Exists`) handles all upgrades. `concurrency: 1` ensures only one node is out of service at a time, preserving etcd quorum throughout.

### Upgrade Procedure (Summary)

1. Update the k3s version tag in `platform/upgrade/upgrade-plans/plan-server.yaml` in Git.
2. FluxCD reconciles the change; system-upgrade-controller picks up the new version.
3. Each node is cordoned, drained, upgraded, and uncordoned in sequence. etcd quorum is maintained (2 of 3 members remain active at all times).
4. Verify node versions with `kubectl get nodes` and review Prometheus alerts for post-upgrade anomalies.

> Full upgrade runbook: [`docs/operations/runbooks/k3s-upgrade.md`](../operations/runbooks/k3s-upgrade.md)

---

## Resource Sizing

All three k3s nodes are **Lenovo ThinkCentre M93p** small form-factor machines — identical hardware makes for predictable behaviour and simplified maintenance.

| Node | CPU | RAM | Storage | Role |
|---|---|---|---|---|
| `tywin` | Intel Core i5-4570T (4c/4t @ 2.9GHz, 35W TDP) | 16 GB DDR3 | 256 GB SSD | Control-plane + worker (~14 GB schedulable after CP overhead) |
| `jaime` | Intel Core i5-4570T (4c/4t @ 2.9GHz, 35W TDP) | 16 GB DDR3 | 256 GB SSD | Control-plane + worker (~14 GB schedulable after CP overhead) |
| `tyrion` | Intel Core i5-4570T (4c/4t @ 2.9GHz, 35W TDP) | 16 GB DDR3 | 256 GB SSD | Control-plane + worker (~14 GB schedulable after CP overhead) |

> **Planned CPU upgrade:** All three nodes will be upgraded to Intel Core i7-4790T (4c/8t @ 2.7GHz base / 3.9GHz turbo, 45W TDP) when parts arrive, doubling thread count. No cluster changes required — nodes are drained, upgraded, and rejoined one at a time.

**Persistent storage** is provided entirely by TrueNAS via NFS. No node-local PersistentVolumes are used in steady state, which means pods can reschedule freely across workers without data affinity constraints.
