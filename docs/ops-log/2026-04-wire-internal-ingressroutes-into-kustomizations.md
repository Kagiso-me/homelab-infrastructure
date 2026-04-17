# 2026-04 — DEPLOY: Wire internal IngressRoutes into kustomizations

**Operator:** Kagiso
**Type:** `DEPLOY`
**Components:** Flux · Kustomization · traefik-internal · IngressRoute
**Commit:** —
**Downtime:** None

---

## What Changed

Added `ingressroute-internal.yaml` files to all app kustomizations that were missing them. Each app that has an external-facing `IngressRoute` now also has a corresponding internal one on `traefik-internal` for `*.local.kagiso.me` access without Authentik.

---

## Why

After setting up `traefik-internal`, apps needed internal IngressRoutes to actually be reachable on LAN. The external routes had Authentik forward-auth middleware applied — fine for external access, but a pain for internal tooling and local development. The internal routes skip auth entirely, relying on network-level isolation (LAN only).

Several apps had been added before `traefik-internal` existed and their kustomizations only listed the external IngressRoute. This sweep added the missing internal routes.

---

## Details

Apps updated (internal route added):
- `vaultwarden` → `vault.local.kagiso.me`
- `nextcloud` → `cloud.local.kagiso.me`
- `immich` → `photos.local.kagiso.me`
- `n8n` → `n8n.local.kagiso.me`
- `seerr` → `requests.local.kagiso.me`
- `miniflux` → `rss.local.kagiso.me`

Each `ingressroute-internal.yaml` uses `entryPoints: [websecure-int]` and no middleware.

---

## Outcome

- All apps reachable on LAN via `*.local.kagiso.me` without Authentik ✓
- Flux reconciles all kustomizations cleanly ✓
- External routes unchanged — Authentik still enforced externally ✓

---

## Related

- Internal Traefik: `platform/networking/traefik-internal/`
- Wildcard DNS: `docs/ops-log/2026-04-add-local-kagiso-me-wildcard-dns-for-internal-traefik.md`
