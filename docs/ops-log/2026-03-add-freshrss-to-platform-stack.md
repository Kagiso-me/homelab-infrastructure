# 2026-03 — DEPLOY: Add FreshRSS to platform-stack

**Operator:** Kagiso
**Type:** `DEPLOY`
**Components:** FreshRSS · Docker Compose · varys · RSS
**Commit:** —
**Downtime:** None

---

## What Changed

Added FreshRSS (self-hosted RSS aggregator) to the `platform-stack` Docker Compose stack on varys. Exposed at `rss.local.kagiso.me` via Traefik.

---

## Why

RSS is the most reliable way to follow technical blogs, Hacker News, and homelab community sites without algorithmic filtering. Google Reader's shutdown demonstrated the risk of relying on a hosted RSS service. FreshRSS self-hosts the entire feed aggregation — the feeds you follow, your read/unread state, and starred items are all yours.

---

## Details

- **Image**: `freshrss/freshrss:latest` (later pinned via Renovate)
- **Database**: SQLite (single-user, no need for PostgreSQL)
- **Storage**: named Docker volume for data persistence
- **Exposure**: Traefik on `rss.local.kagiso.me`, Authentik forward auth
- **Feeds imported**: ~40 subscriptions from OPML export

---

## Outcome

- FreshRSS running, feeds syncing ✓
- OPML import completed ✓
- Accessible from browser and FreshRSS iOS app ✓

---

## Related

- Compose: `host-services/varys/platform-stack/docker-compose.yml`
