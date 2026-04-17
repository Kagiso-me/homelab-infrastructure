# 2026-03 — DEPLOY: Add Immich and n8n deployments

**Operator:** Kagiso
**Type:** `DEPLOY`
**Components:** Immich · n8n · PostgreSQL · Redis · SOPS
**Commit:** —
**Downtime:** None (new deployments)

---

## What Changed

Deployed Immich (self-hosted Google Photos alternative) and n8n (self-hosted workflow automation) to the cluster. Both use the shared PostgreSQL and Redis instances.

---

## Why

**Immich:** Google Photos has 15GB free, then charges. More importantly, every photo taken by family is on Google's infrastructure. Immich provides the same ML-powered search, face recognition, and mobile backup — entirely self-hosted. The k3s cluster has enough CPU for the ML microservices (machine learning runs on the same nodes as the rest of the workloads, using time-sliced CPU).

**n8n:** Automation glue for the homelab. Connects services that don't natively talk to each other — Immich album creation from Nextcloud events, Sonarr notification reformatting, scheduled reports to Discord. Alternative to Zapier/Make but entirely self-hosted.

---

## Details

**Immich:**
- HelmRelease in `apps` namespace, upstream chart from `immich-charts`
- PostgreSQL database `immich` with pgvector, cube, earthdistance, unaccent, pg_trgm extensions (see PostgreSQL bootstrap ops-log)
- Redis: shared cluster Redis instance
- Machine learning microservice: enabled, 2 CPU request, 4GB memory limit
- Storage: NFS PVC for photo library (`/mnt/tank/immich`)
- Mobile app: Immich iOS app configured to sync camera roll

**n8n:**
- HelmRelease in `apps` namespace
- PostgreSQL database `n8n`
- Exposed at `n8n.kagiso.me` behind Authentik
- Initial workflows: Sonarr → Discord, Immich weekly digest → Discord

---

## Outcome

- Immich running, ML microservices healthy ✓
- Camera roll backup confirmed from iOS app ✓
- n8n running, initial workflows active ✓
- Both services on shared PostgreSQL ✓

---

## Related

- PostgreSQL bootstrap: `docs/ops-log/2026-04-08-postgresql-bootstrap.md`
- Immich HelmRelease: `apps/base/immich/helmrelease.yaml`
- n8n HelmRelease: `apps/base/n8n/helmrelease.yaml`
