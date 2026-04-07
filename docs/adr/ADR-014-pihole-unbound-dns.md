# ADR-014: Pi-hole + Unbound as the Homelab DNS Stack

**Status:** Accepted — 2026-04-07
**Deciders:** Kagiso
**Context:** DNS architecture for the homelab LAN

---

## Context

Every device on the LAN needs DNS resolution. The requirements are:

1. **Split DNS** — `*.kagiso.me` and `*.local.kagiso.me` must resolve to internal Traefik IPs on the LAN, not to Cloudflare's anycast IPs or public routes.
2. **Ad/tracker blocking** — network-wide, covering all devices without per-device configuration.
3. **Privacy** — DNS queries should not be visible to third-party resolvers (Cloudflare, Google, ISP).
4. **Reliability** — DNS must survive Kubernetes failures, varys maintenance, and control plane outages.
5. **DNSSEC** — responses should be cryptographically validated.

---

## Options Considered

### Option 1: Router/USG as DNS (status quo before this ADR)

The UniFi USG forwards DNS to Cloudflare (`1.1.1.1`). Split DNS would require custom dnsmasq config on the USG, which gets wiped on every re-provisioning. No ad blocking. No privacy.

**Rejected** — no split DNS persistence, no ad blocking, no privacy.

### Option 2: Pi-hole forwarding to Cloudflare DoH (cloudflared)

Pi-hole handles split DNS and ad blocking. Upstream queries are forwarded to Cloudflare via DNS-over-HTTPS using `cloudflared` as a local proxy. Queries are encrypted in transit, but Cloudflare still sees every domain queried.

**Rejected** — still requires trusting a third-party resolver. Adds cloudflared as an extra dependency.

### Option 3: Pi-hole + Unbound (chosen)

Pi-hole handles split DNS and ad blocking. Upstream queries are handled by Unbound, a validating recursive resolver. Unbound queries root nameservers directly and follows referrals to authoritative nameservers — no third-party resolver is involved at all.

**Chosen** — fully self-contained, no external DNS dependency for resolution, DNSSEC validated.

---

## Decision

Deploy **Pi-hole + Unbound** on `hodor` (dedicated hodor, `10.0.10.15`).

- **Pi-hole** handles split DNS (dnsmasq wildcards) and network-wide ad/tracker blocking.
- **Unbound** handles all recursive resolution upstream of Pi-hole.
- **hodor** is a dedicated appliance node — independent of the Kubernetes cluster and varys.

---

## DNS Architecture

```
LAN device
  │  (DNS query)
  ▼
Pi-hole (hodor, 10.0.10.15:53)
  │  Split DNS rules checked first:
  │    *.kagiso.me       → 10.0.10.110  (traefik-external)
  │    *.local.kagiso.me → 10.0.10.111  (traefik-internal)
  │  Ad/tracker domains → blocked (NXDOMAIN)
  │  All other queries forwarded to:
  ▼
Unbound (127.0.0.1:5335)
  │  Recursive resolution from root:
  │    . (root) → TLD nameservers → authoritative nameservers
  ▼
Authoritative DNS answer (no third party involved)
```

### Split DNS — Two Tiers

| Wildcard | IP | Purpose |
|----------|-----|---------|
| `*.kagiso.me` | `10.0.10.110` | External Traefik — public-facing apps. Same cert as public DNS. |
| `*.local.kagiso.me` | `10.0.10.111` | Internal Traefik — LAN-only apps, admin UIs, never publicly routable. |

The `*.local.kagiso.me` wildcard is more specific than `*.kagiso.me` — dnsmasq applies longest-match first, so `vault.local.kagiso.me` correctly resolves to `10.0.10.111` rather than `10.0.10.110`.

### Internal Ingress Tier

The `*.local.kagiso.me` wildcard enables a dedicated internal Traefik instance (`traefik-internal`, `10.0.10.111`) that is:

- Not exposed to the internet (private IP, no Cloudflare record)
- Always reachable from LAN regardless of external Traefik state
- Serving valid TLS via a Let's Encrypt wildcard cert for `*.local.kagiso.me` (DNS-01 via Cloudflare)
- Free of CrowdSec (LAN traffic only)

Admin tools (Grafana, Prometheus, Traefik dashboard) are only routed through `traefik-internal`. User apps (Nextcloud, Vaultwarden, Immich, n8n, Authentik) are routed through both.

---

## Blocklist Strategy (Balanced)

| List | Category |
|------|----------|
| Steven Black (unified) | Baseline ads/trackers (Pi-hole default) |
| oisd big | Broad ads, trackers, malware — low false positives |
| hagezi Pro | Comprehensive ads, trackers, telemetry |
| hagezi Threat Intelligence Feeds | Malware, phishing, ransomware C2 |

Aggressive lists (e.g. hagezi Ultimate) are deliberately avoided — they block legitimate services and require frequent whitelist maintenance.

---

## Reliability

| Failure scenario | Impact |
|-----------------|--------|
| hodor (RPi) offline | DNS falls back to `1.1.1.1` (UniFi DNS Server 2). Split DNS and ad blocking lost, internet continues. |
| varys offline | No DNS impact — hodor is independent. |
| Kubernetes cluster down | No DNS impact — hodor is independent. |
| traefik-external scaled to 0 | `*.kagiso.me` routes unreachable from internet. LAN devices still resolve via Pi-hole but get no response from 10.0.10.110. `*.local.kagiso.me` unaffected. |
| traefik-internal offline | `*.local.kagiso.me` routes unreachable. External routes unaffected. |

### Redundancy Roadmap

A second Pi-hole instance will be deployed on varys as DNS Server 2 (UniFi DHCP). This provides full DNS redundancy — hodor offline means varys takes over for all DNS including split DNS and ad blocking.

---

## Consequences

- All LAN devices automatically get split DNS and ad blocking via DHCP (no per-device config).
- New internal apps on `*.local.kagiso.me` require zero DNS changes — wildcard covers them.
- New public apps on `*.kagiso.me` require zero DNS changes — wildcard covers them on LAN.
- DNS queries never leave the home network to a third-party resolver.
- DNSSEC is validated for all upstream domains by Unbound.
- hodor must be maintained as an always-on appliance.

---

## References

- [hodor/docs/01_pihole.md](../../hodor/docs/01_pihole.md) — Pi-hole setup guide
- [hodor/docs/02_unbound.md](../../hodor/docs/02_unbound.md) — Unbound setup guide
- [Architecture: Networking](../architecture/networking.md)
