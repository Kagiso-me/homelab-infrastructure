# 2026-03 — DEPLOY: Add central PostgreSQL and Redis to platform

**Operator:** Kagiso
**Type:** `DEPLOY`
**Components:** PostgreSQL · Redis · Bitnami · custom Helm charts · databases namespace
**Commit:** —
**Downtime:** None (new deployment)

---

## What Changed

Deployed a single shared PostgreSQL instance and a single shared Redis instance to the `databases` namespace. All applications use these shared instances rather than bundled per-app database deployments.

---

## Why

Most Helm charts bundle their own PostgreSQL and Redis instances. Deploying 6 apps means 6 PostgreSQL pods and 6 Redis pods — wasteful on a 3-node homelab with limited RAM. A shared model reduces database pod count from 12 to 2, freeing ~3GB of memory across the cluster.

It also centralises backup — one Velero schedule for the `databases` namespace covers all app data, rather than needing per-app backup strategies.

The trade-off is single point of failure and blast radius: if the shared PostgreSQL goes down, all apps lose their database simultaneously. Acceptable for a homelab; not for production.

---

## Details

- **PostgreSQL**: custom HelmRelease using Bitnami PostgreSQL chart, pinned version, persistence on `nfs-databases` StorageClass
- **Redis**: custom HelmRelease using Bitnami Redis chart, persistence disabled (cache only — data is ephemeral), auth via SOPS secret
- **Strategy**: ADR written — upstream charts for apps, custom charts for shared infrastructure (PostgreSQL, Redis)
- **Namespace**: `databases`, separate from `apps` for RBAC and network policy isolation
- **Connection string format**: `postgresql://user:pass@postgresql-primary.databases.svc.cluster.local:5432/dbname`

---

## Outcome

- Shared PostgreSQL and Redis running in `databases` namespace ✓
- No bundled databases in any app HelmRelease ✓
- All apps connecting to shared instances ✓
- ~3GB memory freed vs per-app database model ✓

---

## Related

- PostgreSQL HelmRelease: `platform/databases/postgresql/helmrelease.yaml`
- Redis HelmRelease: `platform/databases/redis/helmrelease.yaml`
- Bootstrap procedure: `docs/ops-log/2026-04-08-postgresql-bootstrap.md`
- ADR: chart sourcing strategy documented in `docs/adr/`
