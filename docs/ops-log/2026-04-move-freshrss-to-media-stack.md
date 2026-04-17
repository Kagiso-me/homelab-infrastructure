# 2026-04 — DEPLOY: Move FreshRSS to media-stack

**Operator:** Kagiso
**Type:** `DEPLOY`
**Components:** FreshRSS · Docker Compose · varys · Miniflux
**Commit:** —
**Downtime:** ~5 minutes (FreshRSS unavailable during compose stack change)

---

## What Changed

Moved FreshRSS from `platform-stack` to `media-stack` on varys. Shortly after, FreshRSS was superseded by Miniflux running in k3s and decommissioned.

---

## Why

The `platform-stack` on varys was getting cluttered — it mixed monitoring tools (Uptime Kuma, Glance) with media/content tools (FreshRSS). Logical separation between platform tooling and media/content helps manage the compose files and restart them independently.

FreshRSS was later replaced by Miniflux in k3s because Miniflux is more actively developed, has a cleaner API, and runs better in the cluster than as a Docker container on varys. The OPML subscriptions transferred directly.

---

## Details

- FreshRSS service definition moved from `platform-stack/docker-compose.yml` to `media-stack/docker-compose.yml`
- Volume renamed for consistency with media-stack naming convention
- Data migrated: exported OPML from FreshRSS, imported into Miniflux after k3s deployment
- FreshRSS removed from compose files after Miniflux confirmed working

---

## Outcome

- FreshRSS running in media-stack during transition ✓
- Miniflux deployed to k3s, subscriptions migrated ✓
- FreshRSS decommissioned cleanly ✓

---

## Related

- Miniflux HelmRelease: `apps/base/miniflux/helmrelease.yaml`
- media-stack: `host-services/varys/media-stack/docker-compose.yml`
