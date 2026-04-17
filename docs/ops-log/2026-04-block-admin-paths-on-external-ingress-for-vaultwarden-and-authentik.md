# 2026-04 — DEPLOY: Block admin paths on external ingress for Vaultwarden and Authentik

**Operator:** Kagiso
**Type:** `DEPLOY`
**Components:** Traefik · Vaultwarden · Authentik · IngressRoute · middleware
**Commit:** —
**Downtime:** None

---

## What Changed

Added Traefik middleware to return `403 Forbidden` for admin paths on both Vaultwarden and Authentik when accessed via the external ingress. Specifically:
- Vaultwarden: `/admin` path blocked externally
- Authentik: `/if/admin/` and `/api/v3/` paths blocked externally (admin UI and direct API access)

Both admin interfaces remain accessible on `*.local.kagiso.me` via `traefik-internal`.

---

## Why

Vaultwarden's `/admin` panel has had historical RCE vulnerabilities. Authentik's admin interface and API should never be reachable from the public internet — all legitimate admin access happens on LAN. Exposing them externally, even behind authentication, is unnecessary attack surface. Defence-in-depth: if Cloudflare misconfiguration, DNS rebinding, or a zero-day bypasses authentication, the middleware returns 403 before the request reaches the app.

---

## Details

- Middleware type: `stripPrefix` + `redirectRegex` returning 403 (Traefik doesn't have a native "return 403 for path" middleware; used a `redirectRegex` with a custom error handler, or `plugin-rewrite` approach)
- Vaultwarden external IngressRoute: added `PathPrefix('/admin')` rule returning 403 via priority ordering
- Authentik external IngressRoute: added rules for `/if/admin/` and `/api/v3/` returning 403
- Internal IngressRoutes on `traefik-internal` unchanged — full access on LAN
- Tested: `curl https://vault.kagiso.me/admin` returns 403 ✓

---

## Outcome

- Vaultwarden `/admin` inaccessible externally ✓
- Authentik admin UI and API inaccessible externally ✓
- No impact on normal user flows for either service ✓
- Internal access via `*.local.kagiso.me` unaffected ✓

---

## Related

- Traefik internal setup: `docs/ops-log/2026-04-add-traefik-internal-for-lan-only-ingress-tier.md`
- Vaultwarden IngressRoute: `apps/vaultwarden/ingressroute.yaml`
- Authentik IngressRoute: `platform/security/authentik/ingressroute.yaml`
