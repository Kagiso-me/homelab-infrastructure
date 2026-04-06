
# ADR-011 — Central PostgreSQL and Redis on Control Plane

**Status:** Amended — 2026-04-06
**Date:** 2026-03-24
**Deciders:** Platform team

---

## Context

Applications being deployed to this cluster (Nextcloud, Authentik, and others)
all require a relational database and a cache/session store. Two architectural
questions arise:

1. **Central shared instance or per-app instances?**
2. **Which node to run them on, and why?**

---

## Decision

**One central PostgreSQL instance and one central Redis instance**, both in
the `databases` namespace.

- **PostgreSQL** — `nfs-databases` StorageClass (dedicated NFS export on
  TrueNAS, no uid squash). No node affinity — can schedule on any node.
- **Redis** — `local-path`, pinned hard to `tywin` by hostname. Redis is a
  cache; data loss on node failure is acceptable. Pinning to `tywin` is stable
  because `tywin` going down means full etcd quorum loss anyway.

Each application gets its own database and user on the shared PostgreSQL
instance. All applications share the single Redis instance.

### Amendment — 2026-04-06

Original decision used `local-path` for both PostgreSQL and Redis, pinned to
the control-plane role (not a specific hostname). When `jaime` went
unreachable, PostgreSQL and Redis PVs were stuck on that node and could not
reschedule — taking down all applications despite the other two nodes being
healthy. This proved that `local-path` for PostgreSQL is not viable on a
3-node HA etcd cluster where any node can go down independently.

PostgreSQL moved to a dedicated `nfs-databases` NFS export (separate from the
app `nfs-truenas` export) which uses `maproot_user=root` with no `mapall`
squash, preserving container uid 999. Redis remains on `local-path` pinned to
`tywin` by hostname — the original `control-plane role` selector was the
specific failure: it allowed the PV to land on any control-plane node.

---

## PostgreSQL over MySQL

Authentik requires PostgreSQL — it does not support MySQL. Since the database
must support the full app catalogue, PostgreSQL is the only viable choice.
Nextcloud, Vaultwarden, and most modern self-hosted applications support
PostgreSQL natively.

## Bitnami chart over CloudNativePG

CloudNativePG is a full Kubernetes operator with automatic failover, streaming
replication, and connection pooling. These features are valuable for
multi-replica HA deployments.

For this cluster, PostgreSQL is intentionally pinned to a single node with
local storage — HA replication is not the goal. CloudNativePG's operator
overhead and added complexity are not justified. Bitnami's PostgreSQL chart
is a straightforward StatefulSet, well-documented, and trivially configurable.

If the platform scales to require HA PostgreSQL, CloudNativePG migration is
a well-trodden path.

## Migration path: first-party PostgreSQL chart

A production-grade PostgreSQL chart is maintained in the
[kagiso-me/charts](https://github.com/Kagiso-me/charts) repository
(`https://kagiso-me.github.io/charts`, indexed on
[Artifact Hub](https://artifacthub.io/packages/search?repo=kagiso-me)).

The first-party chart enforces stricter defaults than the Bitnami chart:
schema-validated values, non-root security context, `existingSecret` for all
credentials, and honest resource limits. Migration from Bitnami to the
first-party chart is the planned upgrade path and requires only a
HelmRepository + HelmRelease swap — no data migration, since the PostgreSQL
data format is chart-agnostic.

## Central shared instance over per-app instances

| Criterion | Per-app instances | Central instance |
|-----------|------------------|-----------------|
| Resource usage | One StatefulSet per app | One StatefulSet total |
| Operational overhead | N instances to upgrade and monitor | One instance |
| Cross-app queries | Not possible | Possible (rarely needed) |
| Blast radius of DB failure | One app affected | All apps affected |
| Namespace isolation | Each app fully isolated | Per-database/user isolation |

For a homelab with 3-5 applications, the operational overhead of multiple
independent instances outweighs the blast radius benefit. Per-database and
per-user permissions on a shared instance provide sufficient isolation. If an
application requires its own instance for security or version reasons, it can
opt out of the shared instance independently.

## Control-plane placement

PostgreSQL and Redis are both pinned to `tywin` (control plane) via
`nodeAffinity` + `toleration` for the `node-role.kubernetes.io/control-plane`
taint.

**Why the control plane:**

- `tywin` is the most operationally protected node. It hosts etcd, the k8s API
  server, and the scheduler — it is never drained or rebooted casually. It is
  the last node to be touched during any maintenance.
- `local-path` storage is node-local. A pod using a `local-path` PV must
  always schedule on the same node as the PV (enforced by the provisioner's
  `nodeAffinity` on the PV). Since the pod is permanently tied to one node
  anyway, it should be the most reliable one.
- The alternative — pinning to a specific worker — offers no advantage (workers
  are less protected than the control plane) and loses the control plane's
  implicit operational protection.

**Trade-off acknowledged:** if `tywin` goes down, both the k8s API server and
all databases go down simultaneously. For a homelab where `tywin` downtime
means full cluster downtime regardless, this is an acceptable coupling.

## local-path storage over NFS

NFS is unsuitable for database workloads. Both PostgreSQL (WAL writes) and
Redis (AOF persistence) write frequently to disk. NFS causes stale file handle
failures on any server blip, silently dropping writes. See ADR-009 for the
full analysis of this failure mode.

`local-path` provides local disk performance with no network dependency.

## No memory limits on PostgreSQL

PostgreSQL is not given a memory limit in the HelmRelease. If PostgreSQL is
OOM-killed, in-flight transactions are lost and recovery may be required.
Allowing PostgreSQL to use available RAM is preferable to hard-capping it.
A memory request is set so the scheduler accounts for it in placement
decisions.

Redis is given a memory limit since it is a cache — eviction and reconnection
are designed-in behaviours, not failure modes.

---

## Consequences

- All apps connect to `postgresql.databases.svc.cluster.local:5432`
- All apps connect to `redis-master.databases.svc.cluster.local:6379`
- Per-app database users are provisioned manually via `kubectl exec` into the
  PostgreSQL pod when each app is deployed
- PostgreSQL superuser password is in `platform/databases/postgresql/secret.yaml` (SOPS-encrypted)
- Redis auth password is in `platform/databases/redis/secret.yaml` (SOPS-encrypted)
- Deployed by `platform-databases` Flux Kustomization, depends on `platform-namespaces`

## Adding a new app database

```bash
# Get the postgres superuser password
kubectl get secret postgresql-secret -n databases -o jsonpath='{.data.postgres-password}' | base64 -d

# Exec into the pod
kubectl exec -it postgresql-0 -n databases -- psql -U postgres

# Create the database and user
CREATE DATABASE appname;
CREATE USER appname WITH PASSWORD 'strong-password';
GRANT ALL PRIVILEGES ON DATABASE appname TO appname;
\q
```
