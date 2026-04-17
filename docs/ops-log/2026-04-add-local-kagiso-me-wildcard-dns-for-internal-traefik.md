# 2026-04 — DEPLOY: Add *.local.kagiso.me wildcard DNS for internal Traefik

**Operator:** Kagiso
**Type:** `DEPLOY`
**Components:** Pi-hole · MikroTik · DNS · traefik-internal
**Commit:** —
**Downtime:** None

---

## What Changed

Added a wildcard DNS entry `*.local.kagiso.me → 10.0.10.111` in Pi-hole (primary DNS) and as a static DNS record in MikroTik (fallback). This resolves all `*.local.kagiso.me` hostnames to the `traefik-internal` MetalLB IP on LAN.

---

## Why

`traefik-internal` was deployed and services had `Host(*.local.kagiso.me)` IngressRoutes, but DNS wasn't resolving those names — browsers got NXDOMAIN. Each subdomain needed a separate DNS entry, which doesn't scale. A wildcard record covers all current and future `*.local.kagiso.me` subdomains with a single DNS entry.

---

## Details

- **Pi-hole**: Custom DNS → `local.kagiso.me` → `10.0.10.111` (Pi-hole supports wildcard via dnsmasq `address=/local.kagiso.me/10.0.10.111`)
- **MikroTik**: Static DNS entry `*.local.kagiso.me` → `10.0.10.111` as fallback for when Pi-hole is unavailable
- **IP**: `10.0.10.111` is `traefik-internal`'s MetalLB LoadBalancer IP
- **TLS**: cert-manager issues wildcard cert for `*.local.kagiso.me` via Cloudflare DNS-01 challenge (works on LAN, no HTTP-01 needed)
- Services reachable after DNS propagation: `grafana.local.kagiso.me`, `prometheus.local.kagiso.me`, `longhorn.local.kagiso.me`

---

## Outcome

- All `*.local.kagiso.me` hostnames resolving on LAN ✓
- Internal services reachable by hostname with valid TLS ✓
- No per-subdomain DNS entries needed ✓

---

## Related

- traefik-internal deploy: `docs/ops-log/2026-04-add-traefik-internal-for-lan-only-ingress-tier.md`
- Pi-hole config: managed via bran Ansible role
