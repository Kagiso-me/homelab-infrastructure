# 2026-04 — DEPLOY: Apply secure-headers, compress, and crowdsec-bouncer middlewares globally

**Operator:** Kagiso
**Type:** `DEPLOY`
**Components:** Traefik · CrowdSec · secure-headers middleware · compression
**Commit:** —
**Downtime:** None (middleware applied as Traefik IngressRoute annotations)

---

## What Changed

Applied three Traefik middlewares globally across all external IngressRoutes:
1. **secure-headers** — adds HSTS, X-Frame-Options, X-Content-Type-Options, CSP, and Referrer-Policy headers to every response
2. **compress** — enables Brotli/gzip response compression
3. **crowdsec-bouncer** — integrates CrowdSec's real-time IP ban list as a Traefik plugin; blocked IPs get a 403 before hitting any upstream service

---

## Why

All three were configured individually for some services but not applied consistently. Any service without `secure-headers` was returning bare responses with no security headers — an easy red flag in browser dev tools and security scanners. CrowdSec was deployed and generating bans but the bouncer wasn't actually enforcing them at the edge, making the CrowdSec deployment cosmetic.

---

## Details

- `secure-headers` middleware defined as a `Middleware` CRD in `platform` namespace, referenced by all external IngressRoutes
- HSTS: `max-age=31536000; includeSubDomains`
- CSP: `default-src 'self'` with per-service overrides where needed (Grafana, Nextcloud require looser policies)
- `compress` middleware: Brotli preferred, gzip fallback, min response size 1024 bytes
- `crowdsec-bouncer`: Traefik plugin pulling ban decisions from CrowdSec local API every 30s; returns 403 with no body to banned IPs
- Internal IngressRoutes (`*.local.kagiso.me`) excluded from crowdsec-bouncer (LAN traffic only)

---

## Outcome

- All external services now return full security headers ✓
- CrowdSec bans enforced at ingress edge ✓
- Response compression active — measurable reduction in payload sizes ✓
- No regressions on existing services ✓

---

## Related

- CrowdSec deployment: `platform/security/crowdsec/`
- Traefik middleware definitions: `platform/networking/traefik/middlewares.yaml`
