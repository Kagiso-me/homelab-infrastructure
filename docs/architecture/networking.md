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
| bran | 10.0.10.9 | RPi 4 — Tailscale exit node, WOL proxy, GitHub Actions runners |

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
- **Reachable from:** LAN only (MikroTik static DNS resolves `*.local.kagiso.me` to `10.0.10.111`)
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
  │  (DNS: *.local.kagiso.me → 10.0.10.111 via MikroTik static DNS)
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

All cluster services are accessed via hostnames. DNS is handled by the MikroTik router for LAN resolution, using its built-in adblock and static DNS entries for split DNS.

### MikroTik — LAN DNS

**The MikroTik router (`10.0.10.1`)** is the DNS server for every device on the LAN. UniFi DHCP hands out `10.0.10.1` as DNS Server 1. The MikroTik forwards unmatched queries to upstream resolvers (Cloudflare, Google).

```
LAN device
  │
  ▼
MikroTik (10.0.10.1:53)
  │  Static DNS entries (longest match first):
  │    *.local.kagiso.me  → 10.0.10.111  (traefik-internal)
  │    *.kagiso.me        → 10.0.10.110  (traefik-external)
  │  Adblock domains      → blocked (NXDOMAIN)
  │  All other queries:
  ▼
Upstream resolver (1.1.1.1 / 8.8.8.8)
```

**MikroTik static DNS entries:**

| Pattern | IP | Purpose |
|---------|-----|---------|
| `*.kagiso.me` | `10.0.10.110` | External Traefik — public-facing apps |
| `*.local.kagiso.me` | `10.0.10.111` | Internal Traefik — LAN-only apps and admin tools |

Individual Docker/NPM services that aren't covered by these wildcards get explicit A records on the MikroTik.

**Ad blocking:** MikroTik built-in adblock feature (router-native, no external process to maintain).

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
2. That is all — the MikroTik wildcard static entry `*.local.kagiso.me → 10.0.10.111` handles DNS automatically. No DNS changes needed.

### Adding a New Public Service

1. Create an IngressRoute pointing to `websecure` with `Host(*.kagiso.me)`.
2. Add an ingress rule to `/etc/cloudflared/config.yml` on varys and restart cloudflared.
3. Add a proxied CNAME in Cloudflare DNS (`cloudflared tunnel route dns homelab <hostname>`).

### DNS Redundancy

| DNS Server | IP | Notes |
|------------|-----|-------|
| DNS Server 1 | `10.0.10.1` (MikroTik) | Primary — adblock + split DNS |
| DNS Server 2 | `1.1.1.1` | Fallback — internet DNS only if router DNS process fails |

If the MikroTik DNS process fails, clients fall back to `1.1.1.1` — internet DNS continues but split DNS is lost. This is acceptable; `*.kagiso.me` is publicly routable and the risk window is short.

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
  DNS Server 1: 10.0.10.1    (MikroTik — adblock + split DNS)
  DNS Server 2: 1.1.1.1      (Cloudflare — fallback)
```

---

## Related

- [ADR-003: Traefik over nginx-ingress](../adr/ADR-003-traefik-over-nginx-ingress.md)
- [ADR-018: MikroTik Adblock + Static DNS](../adr/ADR-018-mikrotik-adblock-static-dns.md)
- [Guide 05: Networking — MetalLB & Traefik](../guides/05-Networking-MetalLB-Traefik.md)
