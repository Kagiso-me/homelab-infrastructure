# ADR-017 — CrowdSec for Threat Detection and Ingress Blocking

**Status:** Accepted
**Date:** 2026-04-05
**Deciders:** Kagiso

---

## Context

The homelab exposes services publicly via Traefik — Nextcloud, Immich, Authentik, and others
are reachable from the internet through a Cloudflare-proxied domain. Public-facing services
attract automated scanners, brute-force attempts, and exploit probes constantly.

Authentik provides authentication for all applications, but application-level auth does not
stop requests from reaching the application in the first place. A bad actor can still:

- Enumerate endpoints
- Attempt credential stuffing against the Authentik login page
- Probe for known CVEs in application paths

Three approaches were evaluated:

1. **CrowdSec** — collaborative threat intelligence + local behaviour detection + Traefik bouncer
2. **Fail2ban** — log-based IP banning on the host
3. **Cloudflare WAF** — edge-level blocking before requests reach the homelab

---

## Decision

**CrowdSec** deployed in-cluster with the Traefik ForwardAuth bouncer.

---

## Rationale

### CrowdSec over Fail2ban

Fail2ban parses log files and bans IPs via iptables after observing failed attempts. It is
log-file-aware but not Kubernetes-aware — it requires log files on the host, does not
understand container log formats natively, and bans at the host network level rather than
at the ingress controller level.

CrowdSec runs as a Kubernetes DaemonSet, reads container logs via the k3s containerd log
path, understands Traefik's log format natively (via a crowdsec collection), and blocks at
the Traefik layer via ForwardAuth before the request reaches the application. It also shares
threat intelligence across the global CrowdSec community network — IPs that are attacking
other CrowdSec users worldwide are proactively blocked, not just IPs that have attacked
this instance.

### CrowdSec over Cloudflare WAF

Cloudflare's WAF (on the free tier) provides basic protection but advanced WAF rules
require a paid plan. More importantly, Cloudflare WAF operates only on HTTP/HTTPS traffic
reaching Cloudflare-proxied domains. Direct-IP access, internal LAN services, and any
service not behind Cloudflare are unprotected.

CrowdSec operates at the cluster ingress layer — it protects all traffic through Traefik
regardless of how it arrives. The two are complementary: Cloudflare provides edge-level
DDoS protection and caching; CrowdSec handles behaviour-based detection and blocking at
the application ingress layer.

### Architecture

CrowdSec deploys three components:

| Component | Role |
|-----------|------|
| **LAPI** (Local API) | Decision engine — aggregates detections, queries threat intel, manages banlists |
| **Agent** (DaemonSet) | Log parser on every node — reads container logs, detects attack patterns |
| **Bouncer** (Traefik ForwardAuth) | Blocks requests from banned IPs before they reach the application |

The bouncer is wired into Traefik as a global `ForwardAuth` middleware applied to all
routes via the entrypoint middleware chain. Every inbound request is checked against the
CrowdSec LAPI banlist before Traefik routes it. Banned IPs receive a 403 response at the
Traefik layer — the application never sees the request.

CrowdSec uses containerd as the container runtime (k3s does not use Docker), configured
via `container_runtime: containerd` in the Helm values.

---

## Consequences

- All traffic through Traefik is checked against the CrowdSec banlist — adds a small
  latency overhead per request (~1ms for a local LAPI lookup)
- If LAPI is unavailable, the bouncer fails open (requests pass through) to avoid locking
  out legitimate users during a CrowdSec pod restart
- Threat intel sharing requires a CrowdSec account and enrolment key — this is stored as
  a cluster secret
- CrowdSec does not replace Authentik — it operates at the network layer before
  authentication; Authentik operates at the application layer after routing
- False positives are possible — legitimate users from flagged IP ranges may be blocked.
  Decisions can be reviewed and overridden via the CrowdSec CLI (`cscli decisions list`)
