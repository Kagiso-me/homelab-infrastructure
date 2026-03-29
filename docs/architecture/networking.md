
# Architecture — Networking

## Network Design Reference

This document describes the network architecture of the platform, including IP allocation, traffic flow, and component responsibilities.

---

## Physical Network

All nodes are on the same Layer-2 network segment.

| Host | IP | Role |
|------|----|------|
| tywin | 10.0.10.11 | Kubernetes control-plane |
| jaime | 10.0.10.12 | Kubernetes worker |
| tyrion | 10.0.10.13 | Kubernetes worker |
| TrueNAS | 10.0.10.80 | NFS storage |
| Router / DNS | 10.0.10.1 | Default gateway, wildcard DNS |
| Docker host (NUC) | 10.0.10.20 | Intel NUC bare metal — Docker media stack |
| varys | 10.0.10.10 | Control hub (Ansible, kubectl, GitHub runner, Pi-hole, Grafana, Alertmanager, cloudflared) |
| bran | 10.0.10.10 (retiring) | RPi 3B+ — secondary Pi-hole, Tailscale exit node, WOL proxy |

---

## MetalLB IP Pool

MetalLB provides LoadBalancer IP allocation for bare-metal nodes.

**IP pool:** `10.0.10.110 – 10.0.10.115`

This range is reserved exclusively for Kubernetes services. No other devices should be assigned addresses in this range.

| IP | Assignment |
|----|-----------|
| 10.0.10.110 | Traefik ingress (primary) |
| 10.0.10.111–115 | Reserved for additional LoadBalancer services |

MetalLB operates in **Layer-2 mode**. It responds to ARP requests for the allocated IPs, advertising the IP as belonging to the node running the MetalLB speaker. All traffic for the IP arrives at that node and is then forwarded to the appropriate service by kube-proxy.

**Layer-2 limitation:** Only one node handles traffic for a given IP at a time. If that node fails, MetalLB will advertise the IP from a different node, but there is a brief traffic interruption. This is acceptable for a homelab platform.

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
Traefik (10.0.10.110 — internal routing + host matching)
  │
  ▼
Application Service (ClusterIP)
  │
  ▼
Application pod
```

**Key properties of this model:**

- No inbound ports 80/443 required on the router/firewall for public web traffic.
- TLS between browser and Cloudflare Edge is managed automatically by Cloudflare.
- Traffic between Cloudflare Edge and cloudflared is encrypted via the tunnel.
- Traefik still handles internal routing and host-based dispatch to services.

### Traffic Flow — Tailscale (Plex / Remote Admin)

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
Plex service (direct) — or Traefik (10.0.10.110) for other apps
  │
  ▼
Application pod (Plex, SSH target, etc.)
```

---

## DNS Architecture

All cluster services are accessed via hostnames under `kagiso.me`. DNS is split across two layers: Pi-hole for LAN resolution and Cloudflare for public resolution.

### Pi-hole — LAN DNS Server

**Pi-hole runs on varys at `10.0.10.10`** and is the DNS resolver for every device on the LAN. The USG DHCP server hands out `10.0.10.10` as DNS Server 1 to all DHCP clients.

Pi-hole provides:

- **Wildcard DNS:** `*.kagiso.me → 10.0.10.110` (Traefik) — configured as a dnsmasq `address` directive, so every `*.kagiso.me` hostname resolves to Traefik on the LAN without per-service DNS entries.
- **Ad blocking:** Network-wide DNS-based ad blocking for all LAN clients.
- **Split DNS:** Internal services only need a Pi-hole entry — they are invisible from the public internet regardless of whether a TLS certificate exists for them.
- **Upstream DNS:** All other queries are forwarded to Cloudflare `1.1.1.1` / `1.0.0.1` with DNSSEC validation.

```
# Pi-hole wildcard (dnsmasq address directive — auto-configured by Ansible playbook)
address=/kagiso.me/10.0.10.110

# Upstream resolvers (with DNSSEC)
1.1.1.1
1.0.0.1
```

### Cloudflare DNS — Public Access

Public services additionally have proxied CNAME records in Cloudflare DNS pointing to the Cloudflare Tunnel:

```
# Public services — DNS records are proxied through Cloudflare
# These do NOT point directly to 10.0.10.110
grafana.kagiso.me    CNAME  <tunnel-id>.cfargotunnel.com  (proxied)
nextcloud.kagiso.me  CNAME  <tunnel-id>.cfargotunnel.com  (proxied)
immich.kagiso.me     CNAME  <tunnel-id>.cfargotunnel.com  (proxied)
```

External clients resolve to Cloudflare's anycast IPs — the home network IP is never exposed. Traffic is forwarded to the homelab via the Cloudflare Tunnel.

### Split DNS Security Model

> **The TLS certificate does not expose a service. DNS and routing do.**

A service with a valid `*.kagiso.me` certificate is only reachable from the internet if **both** of the following are true:

1. A public Cloudflare DNS record (proxied CNAME to the tunnel) exists for it.
2. A matching hostname ingress rule exists in the `cloudflared` config.

An internal-only service that has a `*.kagiso.me` cert but no Cloudflare DNS record and no tunnel rule is unreachable from WAN. From the LAN, Pi-hole's wildcard resolves it to Traefik; from the internet, the hostname does not resolve at all.

### Adding a New Internal-Only Service

1. Create an `IngressRoute` in k3s with the desired `Host(*.kagiso.me)` rule.
2. That is all — Pi-hole's wildcard `*.kagiso.me → 10.0.10.110` handles DNS automatically on the LAN. No Pi-hole changes needed.

The service is reachable on the LAN. It is not reachable from the WAN.

### Adding a New Public Service

1. Create an `IngressRoute` in k3s with the desired hostname.
2. Add a hostname ingress rule to `/etc/cloudflared/config.yml` on varys and restart `cloudflared`.
3. Add a proxied CNAME record in Cloudflare DNS pointing to the tunnel (`cloudflared tunnel route dns homelab <hostname>` handles this automatically).

---

## TLS Architecture

TLS is handled by cert-manager for all cluster services. cert-manager issues a wildcard `*.kagiso.me` certificate via Let's Encrypt DNS-01 challenge using the Cloudflare API.

**ClusterIssuers:**

| Issuer | Type | Use case |
|--------|------|---------|
| `letsencrypt-prod` | Let's Encrypt (ACME, DNS-01) | Production wildcard `*.kagiso.me` certificate |
| `letsencrypt-staging` | Let's Encrypt Staging (ACME, DNS-01) | Testing certificate issuance without rate-limiting |
| `internal-ca` | Self-signed internal CA | Internal cluster services with no external exposure |

Traefik is configured with a default `TLSStore` that uses the wildcard certificate for all HTTPS ingress routes automatically — no per-service certificate annotations required.

**Certificate flow — all cluster services:**

```
cert-manager requests *.kagiso.me cert from Let's Encrypt
  │
  ▼
Let's Encrypt DNS-01 challenge via Cloudflare API (TXT record created/deleted automatically)
  │
  ▼
Wildcard certificate stored as a Kubernetes Secret in the cert-manager namespace
  │
  ▼
Traefik TLSStore references the wildcard cert — served for all *.kagiso.me IngressRoutes
```

**Certificate flow — public services (Cloudflare Tunnel):**

```
Browser connects to Cloudflare Edge
  │
  ▼
Cloudflare terminates its own TLS (managed certificate, separate from cert-manager)
  │
  ▼
Encrypted tunnel to cloudflared → Traefik (serves wildcard *.kagiso.me cert internally)
```

> **Note:** Plex and remote admin access use Tailscale. Cloudflare's ToS prohibits video streaming proxy through the tunnel.

---

## External Access Architecture

Three access paths serve different use cases:

| Path | Used For | TLS Source | Notes |
|------|----------|-----------|-------|
| Cloudflare Tunnel | All public web services (Grafana, Sonarr, Nextcloud, etc.) | Cloudflare (automatic) | No open inbound ports required |
| Tailscale / Headscale | Plex/media streaming, remote SSH, kubectl | Tailscale (own infrastructure) | Cloudflare ToS prohibits video proxy |
| Direct LAN | All internal traffic | Internal CA (`internal-ca`) | Bypasses Cloudflare entirely |

### Cloudflare Tunnel — Web Services

Services exposed through Cloudflare Tunnel include: Grafana, Sonarr, Radarr, Nextcloud, Immich UI, and other HTTP-based applications. The tunnel is an outbound connection from `cloudflared` (running on varys at `10.0.10.10`), so no inbound firewall rules are needed for web traffic.

### Tailscale / Headscale — Media Streaming and Remote Admin

Plex and any direct media access use Tailscale. Once connected, the client reaches homelab nodes via encrypted peer-to-peer tunnels and can access services at their internal IPs or via Tailscale MagicDNS. Remote SSH to homelab nodes and `kubectl` access also go through Tailscale. Headscale (a self-hosted Tailscale coordination server) runs on varys alongside Pi-hole and cloudflared.

### Direct LAN — Internal Traffic

All traffic from devices on the local network goes directly to `10.0.10.110` (Traefik) via MetalLB, bypassing Cloudflare entirely. Internal DNS resolves `*.kagiso.me` to `10.0.10.110`.

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

The UniFi Security Gateway DHCP server is configured to hand out `10.0.10.10` (varys / Pi-hole) as the DNS server for all LAN clients:

```
UniFi Controller → Networks → [LAN network] → DHCP → DNS Server 1: 10.0.10.10
```

This ensures all devices on the LAN use Pi-hole for DNS resolution, receiving both ad blocking and the `*.kagiso.me` wildcard split DNS automatically.

---

## Related Guides

- [Guide 05: Networking — MetalLB & Traefik](../guides/05-Networking-MetalLB-Traefik.md)
- [ADR-003: Traefik over nginx-ingress](../adr/ADR-003-traefik-over-nginx-ingress.md)
