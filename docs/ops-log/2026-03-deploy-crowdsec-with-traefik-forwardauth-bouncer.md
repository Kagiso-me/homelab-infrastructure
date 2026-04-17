# 2026-03 — DEPLOY: Deploy CrowdSec with Traefik ForwardAuth bouncer

**Operator:** Kagiso
**Type:** `DEPLOY`
**Components:** CrowdSec · Traefik · ForwardAuth bouncer · threat intelligence
**Commit:** —
**Downtime:** None

---

## What Changed

Deployed CrowdSec to the cluster and wired its bouncer into Traefik as a ForwardAuth middleware. Requests from IPs in CrowdSec's community blocklist are rejected at the ingress before reaching any upstream service.

---

## Why

The homelab exposes several services to the internet. Without active threat blocking, every exposed endpoint gets scanned constantly — Shodan, script kiddies, and botnet scanners hit every public IP within minutes of exposure. Cloudflare's free tier provides some protection but doesn't block known bad actors proactively.

CrowdSec is a collaborative IDS/IPS — it shares threat intelligence across all participants. An IP that attacks one CrowdSec-protected homelab gets blocked everywhere. The community blocklist at any given time contains tens of thousands of known-bad IPs.

---

## Details

- **CrowdSec**: deployed in `crowdsec` namespace, in-cluster log collection from Traefik access logs
- **Scenarios**: HTTP brute force, path traversal, bad user agents, port scanning
- **Community blocklist**: CrowdSec CTI pull subscription, updated every 15 minutes
- **Bouncer**: `crowdsec-traefik-bouncer` as Traefik ForwardAuth middleware — returns 403 to banned IPs before the request reaches Traefik routing
- **Local decisions**: manual ban support via `cscli decisions add --ip <ip>`
- **Metrics**: CrowdSec metrics exposed to Prometheus; Grafana dashboard showing geo threat map

---

## Outcome

- CrowdSec active, pulling community blocklist ✓
- Bouncer blocking known-bad IPs at ingress ✓
- Grafana threat map showing blocked countries ✓
- First 24h: 12 IPs blocked from community list ✓

---

## Related

- CrowdSec HelmRelease: `platform/security/crowdsec/helmrelease.yaml`
- Grafana CrowdSec dashboard: imported from CrowdSec hub
