# 2026-04 — DEPLOY: Add platform-stack with Glance and Uptime Kuma

**Operator:** Kagiso
**Type:** `DEPLOY`
**Components:** Glance · Uptime Kuma · Docker Compose · varys
**Commit:** —
**Downtime:** None

---

## What Changed

Added a new `platform-stack` Docker Compose stack on `varys` containing Glance (a customisable homelab dashboard) and Uptime Kuma (uptime and SSL certificate monitoring with alerting).

---

## Why

The cluster had Grafana for deep metrics but nothing for at-a-glance status of all services from a single page — including non-cluster services (Pi-hole, TrueNAS, MikroTik). Glance fills that gap with a lightweight, config-file-driven dashboard.

Uptime Kuma adds HTTP/TCP uptime checks with history graphs and Discord alert integration, catching service availability issues that Prometheus doesn't catch (Prometheus scrapes metrics; Uptime Kuma checks if the service is actually responding to HTTP requests from outside the cluster).

---

## Details

- **Glance**: serves at `glance.local.kagiso.me:8800`, configured via `glance.yml` (RSS feeds, status pages, bookmarks, weather)
- **Uptime Kuma**: serves at `status.local.kagiso.me:3001`, Discord notifications on status change
- **Monitors configured**: all `*.kagiso.me` services, Pi-hole, TrueNAS, MikroTik web UI, bran SSH
- **Alert thresholds**: 2 failed checks before alerting (avoids flapping on brief hiccups)
- Both services in `platform-stack` Compose file on `varys` with named volumes for persistence

---

## Outcome

- Glance dashboard running with all services listed ✓
- Uptime Kuma monitoring all external and internal services ✓
- Discord alerts tested and confirmed ✓

---

## Related

- Compose file: `host-services/varys/platform-stack/docker-compose.yml`
- Glance config: `host-services/varys/platform-stack/glance.yml`
