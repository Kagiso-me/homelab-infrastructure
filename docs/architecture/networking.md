# Architecture — Networking

## Network Design Reference

This document describes the network architecture of the platform, including IP allocation, traffic flow, and component responsibilities.

---

## Physical Network

All nodes are on the same Layer-2 network segment.

| Host | IP | Role |
|------|----|------|
| kube-vip | 10.0.10.100 | Kubernetes API virtual IP |
| tywin | 10.0.10.11 | Kubernetes server node |
| tyrion | 10.0.10.12 | Kubernetes server node |
| jaime | 10.0.10.13 | Kubernetes server node |
| TrueNAS | 10.0.10.80 | NFS storage |
| Router | 10.0.10.1 | Default gateway |
| Docker host (NUC) | 10.0.10.20 | Intel NUC bare metal — Docker media stack |
| varys | 10.0.10.10 | Control hub (Ansible, kubectl, GitHub runner, cloudflared) |
| hodor | 10.0.10.15 | RPi 4 — Primary Pi-hole + Unbound, Tailscale exit node, WOL proxy |

---

## MetalLB IP Pool

MetalLB provides LoadBalancer IP allocation for bare-metal nodes.

**IP pool:** `10.0.10.110 – 10.0.10.115`

This range is reserved exclusively for Kubernetes services. No other devices should be assigned addresses in this range.

| IP | Assignment |
|----|-----------|
| 10.0.10.110 | `traefik-external` — public-facing ingress |
| 10.0.10.111 | `traefik-internal` — LAN-only ingress |
| 10.0.10.112–115 | Reserved for additional LoadBalancer services |

MetalLB operates in **Layer-2 mode**. It responds to ARP requests for the allocated IPs, advertising the IP as belonging to the node running the MetalLB speaker. All traffic for the IP arrives at that node and is then forwarded to the appropriate service by kube-proxy.

**Layer-2 limitation:** Only one node handles traffic for a given IP at a time. If that node fails, MetalLB will advertise the IP from a different node, but there is a brief traffic interruption. This is acceptable for a homelab platform.

---

## Ingress Architecture — Two Tiers

The platform uses two independent Traefik deployments, each with their own MetalLB IP, entrypoint, and TLS certificate.

### traefik-external (`10.0.10.110`)

- **Domain:** `*.kagiso.me`
- **Cert:** Let's Encrypt wildcard via Cloudflare DNS-01
- **Entrypoint:** `websecure` (port 443)
- **Protection:** CrowdSec ForwardAuth middleware on all routes
- **Reachable from:** Internet (via Cloudflare Tunnel) and LAN
- **Apps:** All user-facing apps (Nextcloud, Vaultwarden, Immich, n8n, Authentik)
- **Admin path blocking:** `/admin` (Vaultwarden) and `/if/admin/` (Authentik) return 403 from this entrypoint

### traefik-internal (`10.0.10.111`)

- **Domain:** `*.local.kagiso.me`
- **Cert:** Let's Encrypt wildcard for `*.local.kagiso.me` via Cloudflare DNS-01
- **Entrypoint:** `websecure-int` (port 443)
- **Protection:** None — LAN-only, private IP, unreachable from internet
- **Reachable from:** LAN only (Pi-hole resolves `*.local.kagiso.me` to `10.0.10.111`)
- **Apps:** All user-facing apps (internal routes) + admin-only tools

### App Exposure Model

| App | External (`*.kagiso.me`) | Internal (`*.local.kagiso.me`) |
|-----|--------------------------|-------------------------------|
| Vaultwarden | `vault.kagiso.me` (admin blocked) | `vault.local.kagiso.me` (full access) |
| Nextcloud | `cloud.kagiso.me` | `cloud.local.kagiso.me` |
| Immich | `photos.kagiso.me` | `photos.local.kagiso.me` |
| n8n | `n8n.kagiso.me` | `n8n.local.kagiso.me` |
| Authentik | `auth.kagiso.me` (admin blocked) | `auth.local.kagiso.me` (full access) |
| Grafana | — | `grafana.local.kagiso.me` |
| Prometheus | — | `prometheus.local.kagiso.me` |
| Traefik dashboard | — | `traefik.local.kagiso.me` |

### Maintenance Isolation

Scaling `traefik-external` to 0 makes all public services unreachable from the internet while keeping all `*.local.kagiso.me` routes fully accessible on the LAN. This is the standard maintenance posture.

```bash
# Take external ingress offline
kubectl scale deployment -n ingress traefik --replicas=0

# Restore
kubectl scale deployment -n ingress traefik --replicas=3
```

---

## Traffic Flow — Cloudflare Tunnel (Public Access)

Public services are exposed via Cloudflare Tunnel. There are no open inbound ports on the home network for web traffic.

```
Browser
  │
  ▼
Cloudflare Edge (public IP — TLS terminated here)
  │  (encrypted tunnel — outbound connection initiated by cloudflared)
  ▼
cloudflared daemon (running on varys at 10.0.10.10)
  │
  ▼
traefik-external (10.0.10.110 — CrowdSec check + host matching)
  │
  ▼
Application Service (ClusterIP)
  │
  ▼
Application pod
```

**Key properties:**
- No inbound ports 80/443 required on the router/firewall for public web traffic.
- TLS between browser and Cloudflare Edge is managed automatically by Cloudflare.
- Traffic between Cloudflare Edge and cloudflared is encrypted via the tunnel.
- CrowdSec rate-limiting and IP reputation checking on every external request.

### Traffic Flow — LAN (Internal Access)

```
LAN device
  │  (DNS: *.local.kagiso.me → 10.0.10.111 via Pi-hole)
  ▼
traefik-internal (10.0.10.111 — host matching, no CrowdSec)
  │
  ▼
Application Service (ClusterIP)
  │
  ▼
Application pod
```

### Traffic Flow — Tailscale (Remote Admin / Plex)

Plex and media streaming are accessed remotely via Tailscale. Cloudflare's ToS prohibits proxying video streaming. SSH and kubectl access from remote locations also use Tailscale.

```
Tailscale client (remote device)
  │
  ▼
Tailscale / Headscale coordination server
  │
  ▼
WireGuard-encrypted peer-to-peer tunnel to home network node
  │
  ▼
Plex service (direct) — or traefik-external (10.0.10.110) for other apps
  │
  ▼
Application pod (Plex, SSH target, etc.)
```

---

## DNS Architecture

All cluster services are accessed via hostnames. DNS is handled by Pi-hole on `hodor` for LAN resolution, backed by Unbound for recursive resolution.

### Pi-hole + Unbound — LAN DNS

**Pi-hole runs on hodor at `10.0.10.15`** and is the DNS resolver for every device on the LAN. The USG DHCP server hands out `10.0.10.15` as DNS Server 1.

**Unbound** runs on hodor at `127.0.0.1:5335` as Pi-hole's upstream. It is a recursive resolver — it queries root nameservers directly. No third-party DNS provider (Cloudflare, Google) is involved in resolution.

```
LAN device
  │
  ▼
Pi-hole (10.0.10.15:53)
  │  Split DNS rules (dnsmasq, longest match first):
  │    *.local.kagiso.me  → 10.0.10.111  (traefik-internal)
  │    *.kagiso.me        → 10.0.10.110  (traefik-external)
  │  Ad/tracker domains   → blocked (NXDOMAIN)
  │  All other queries:
  ▼
Unbound (127.0.0.1:5335)
  │  Recursive resolution — no third party
  ▼
Root nameservers → TLD nameservers → Authoritative nameservers
```

**Pi-hole dnsmasq config (`/etc/dnsmasq.d/02-kagiso-local.conf`):**
```conf
# Wildcard — *.local.kagiso.me resolves to internal Traefik (more specific, matched first)
address=/.local.kagiso.me/10.0.10.111

# Wildcard — *.kagiso.me resolves to external Traefik
address=/.kagiso.me/10.0.10.110
```

**Blocklists (balanced tier):** oisd big, hagezi Pro, hagezi Threat Intelligence Feeds, Steven Black.

### Cloudflare DNS — Public Access

Public services have proxied CNAME records in Cloudflare DNS pointing to the Cloudflare Tunnel. External clients resolve to Cloudflare's anycast IPs — the home network IP is never exposed.

```
# Public services — DNS records proxied through Cloudflare
vault.kagiso.me   CNAME  <tunnel-id>.cfargotunnel.com  (proxied)
cloud.kagiso.me   CNAME  <tunnel-id>.cfargotunnel.com  (proxied)
auth.kagiso.me    CNAME  <tunnel-id>.cfargotunnel.com  (proxied)
```

### Split DNS Security Model

> **The TLS certificate does not expose a service. DNS and routing do.**

A service is reachable from the internet only if **both** are true:
1. A public Cloudflare DNS record (proxied CNAME to the tunnel) exists for it.
2. A matching hostname ingress rule exists in the `cloudflared` config.

Admin-only tools (Grafana, Prometheus, Traefik dashboard) have no public DNS record and no tunnel rule — they are unreachable from WAN regardless of their TLS cert.

### Adding a New Internal-Only Service

1. Create an IngressRoute pointing to `websecure-int` with `Host(*.local.kagiso.me)`.
2. That is all — Pi-hole's wildcard `*.local.kagiso.me → 10.0.10.111` handles DNS automatically. No Pi-hole changes needed.

### Adding a New Public Service

1. Create an IngressRoute pointing to `websecure` with `Host(*.kagiso.me)`.
2. Add an ingress rule to `/etc/cloudflared/config.yml` on varys and restart cloudflared.
3. Add a proxied CNAME in Cloudflare DNS (`cloudflared tunnel route dns homelab <hostname>`).

### DNS Redundancy

| DNS Server | IP | Notes |
|------------|-----|-------|
| DNS Server 1 | `10.0.10.15` (hodor) | Primary — Pi-hole + Unbound, split DNS, ad blocking |
| DNS Server 2 | `1.1.1.1` | Fallback — internet DNS only if hodor is offline |

When a second Pi-hole is deployed (target: varys), DNS Server 2 will be updated to its IP for full split-DNS redundancy.

---

## TLS Architecture

TLS is handled by cert-manager for all cluster services.

**ClusterIssuers:**

| Issuer | Type | Use case |
|--------|------|---------|
| `letsencrypt-prod` | Let's Encrypt (ACME, DNS-01) | Production wildcards — `*.kagiso.me` and `*.local.kagiso.me` |
| `internal-ca` | Self-signed internal CA | Internal cluster services with no external exposure |

**Certificates:**

| Certificate | Namespace | Serves |
|-------------|-----------|--------|
| `wildcard-kagiso-me-tls` | `ingress` | All `*.kagiso.me` routes via `traefik-external` TLSStore |
| `wildcard-local-kagiso-me-tls` | `ingress-internal` | All `*.local.kagiso.me` routes via `traefik-internal` TLSStore |

Both certificates are issued via Cloudflare DNS-01 — no public HTTP access is required for issuance. Both auto-renew 15 days before expiry.

---

## Kubernetes Internal Networking

| Component | CIDR | Notes |
|-----------|------|-------|
| Pod network (flannel) | 10.42.0.0/16 | k3s default |
| Service ClusterIP network | 10.43.0.0/16 | k3s default |
| Node network | 10.0.10.0/24 | Physical network |
| MetalLB pool | 10.0.10.110–10.0.10.115 | Subset of node network |

CoreDNS provides in-cluster DNS resolution. Services are reachable within the cluster at:

```
<service>.<namespace>.svc.cluster.local
```

---

## Firewall Rules (UFW, per node)

Applied by `playbooks/security/firewall.yml`:

| Port | Protocol | Purpose |
|------|----------|---------|
| 22 | TCP | SSH (restricted to automation host) |
| 6443 | TCP | Kubernetes API server |
| 10250 | TCP | kubelet metrics |
| 2379–2380 | TCP | etcd (control-plane only) |
| 8472 | UDP | Flannel VXLAN overlay |
| 443 | TCP | HTTPS — Traefik (LAN/Tailscale direct access only) |

### USG DHCP Configuration

```
Settings → Networks → [LAN] → DHCP
  DNS Server 1: 10.0.10.15   (hodor — Pi-hole primary)
  DNS Server 2: 1.1.1.1      (Cloudflare — fallback)
```

---

## Related

- [ADR-003: Traefik over nginx-ingress](../adr/ADR-003-traefik-over-nginx-ingress.md)
- [ADR-014: Pi-hole + Unbound DNS Architecture](../adr/ADR-014-pihole-unbound-dns.md)
- [raspberry-pi/docs/01_pihole.md](../../raspberry-pi/docs/01_pihole.md)
- [raspberry-pi/docs/02_unbound.md](../../raspberry-pi/docs/02_unbound.md)
- [Guide 05: Networking — MetalLB & Traefik](../guides/05-Networking-MetalLB-Traefik.md)
