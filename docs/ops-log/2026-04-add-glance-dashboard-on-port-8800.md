# 2026-04 — DEPLOY: Add Glance dashboard on port 8800

**Operator:** Kagiso
**Type:** `DEPLOY`
**Components:** Glance · varys · Docker Compose
**Commit:** —
**Downtime:** None

---

## What Changed

Moved Glance from the `platform-stack` compose file into its own dedicated stack and exposed it directly on port 8800 of varys for LAN access without going through Traefik.

---

## Why

Glance needs to stay accessible even when the k3s cluster is down — it's a homelab overview dashboard, and its value is highest precisely when something is wrong with the cluster. Routing it through Traefik meant it went dark whenever Traefik was unhealthy. Port 8800 on varys is always reachable on LAN regardless of cluster state.

---

## Details

- Glance listening on `0.0.0.0:8800` in Docker, accessible at `http://varys.local:8800` or `http://10.0.10.x:8800`
- Configuration in `glance.yml`: groups of widgets — cluster services, RSS feeds (self-hosting/homelab blogs), weather, quick links
- No auth — LAN-only, not exposed externally
- Restart policy: `unless-stopped`

---

## Outcome

- Glance accessible on port 8800 directly ✓
- Accessible when cluster is down ✓
- Dashboard shows all homelab services at a glance ✓

---

## Related

- Compose: `host-services/varys/glance/docker-compose.yml`
