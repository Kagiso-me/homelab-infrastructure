# 2026-04 — DEPLOY: Add traefik-internal for LAN-only ingress tier

**Operator:** Kagiso
**Type:** `DEPLOY`
**Components:** Traefik · MetalLB · IngressRoute · internal DNS
**Commit:** —
**Downtime:** None

---

## What Changed

Deployed a second Traefik instance (`traefik-internal`) on a separate MetalLB IP (`10.0.10.111`) dedicated to LAN-only services. Internal services now use `*.local.kagiso.me` hostnames routed through `traefik-internal`, while external-facing services remain on `traefik` (the public-facing instance via Cloudflare tunnel).

---

## Why

Previously, all services — internal admin tools, monitoring dashboards, and external-facing apps — shared a single Traefik instance. This meant internal-only tools (Grafana, Longhorn, Proxmox UI, router management) were technically reachable from the same ingress path as public services, relying solely on Cloudflare tunnel not forwarding those routes. It also made middleware configuration messy: the crowdsec-bouncer and rate-limiting middleware needed to apply to external traffic but not internal.

A dedicated internal Traefik instance gives a clean separation: external traffic can never reach an internal-only IngressRoute by construction, not by routing config.

---

## Details

- **External**: `traefik` on `10.0.10.110` — public-facing, Cloudflare tunnel, crowdsec-bouncer, secure-headers, rate limiting
- **Internal**: `traefik-internal` on `10.0.10.111` — LAN-only, no crowdsec, relaxed CSP for admin UIs
- DNS: `*.local.kagiso.me` → `10.0.10.111` via Pi-hole / MikroTik static DNS
- Existing internal services migrated to `traefik-internal` IngressRoutes: Grafana, Longhorn UI, Prometheus, Alertmanager
- HelmRelease: separate `traefik-internal` release in `platform/networking/traefik-internal/`
- Both instances use the same cert-manager ClusterIssuer but separate Certificate resources

---

## Outcome

- Clean external/internal ingress separation ✓
- Internal services no longer reachable via external Traefik ✓
- `*.local.kagiso.me` resolving correctly on LAN ✓
- Middleware configs simplified — internal instance has no crowdsec or rate limiting ✓

---

## Related

- Wildcard DNS setup: `docs/ops-log/2026-04-add-local-kagiso-me-wildcard-dns-for-internal-traefik.md`
- Traefik internal HelmRelease: `platform/networking/traefik-internal/helmrelease.yaml`
