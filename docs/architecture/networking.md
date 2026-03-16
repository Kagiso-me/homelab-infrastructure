
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
| Proxmox host (NUC) | 10.0.10.20 | Hypervisor |
| docker-vm | 10.0.10.21 | Docker media stack |
| staging-k3s | TBD | Single-node k3s staging |
| RPi | 10.0.10.10 | Control hub |

---

## MetalLB IP Pool

MetalLB provides LoadBalancer IP allocation for bare-metal nodes.

**IP pool:** `10.0.10.110 – 10.0.10.125`

This range is reserved exclusively for Kubernetes services. No other devices should be assigned addresses in this range.

| IP | Assignment |
|----|-----------|
| 10.0.10.110 | Traefik ingress (primary) |
| 10.0.10.111 | Reserved for future use |
| 10.0.10.112–120 | Available for additional LoadBalancer services |

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
cloudflared daemon (running on RPi / Proxmox)
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

### Traffic Flow — WireGuard (Plex / Remote Admin)

Plex and media streaming are accessed remotely via WireGuard VPN. Cloudflare's ToS prohibits proxying video streaming.

```
WireGuard client (remote device)
  │
  ▼
WireGuard VPN (direct tunnel to home network)
  │
  ▼
Traefik (10.0.10.110) — or direct to Plex service
  │
  ▼
Application pod (Plex, SSH target, etc.)
```

---

## DNS Architecture

All cluster services are accessed via hostnames under `kagiso.me` (public domain).

**DNS configuration** (managed in Cloudflare DNS):

```
# Public services — DNS records are proxied through Cloudflare
# These do NOT point directly to 10.0.10.110
grafana.kagiso.me    CNAME  <tunnel-id>.cfargotunnel.com  (proxied)
nextcloud.kagiso.me  CNAME  <tunnel-id>.cfargotunnel.com  (proxied)
immich.kagiso.me     CNAME  <tunnel-id>.cfargotunnel.com  (proxied)
```

Cloudflare proxies the DNS records — external clients resolve to Cloudflare's anycast IPs, not to the home network IP. Traffic is forwarded to the homelab via the Cloudflare Tunnel.

**Internal / direct access** (LAN or WireGuard) continues to use:

```
# Internal wildcard — resolves to Traefik directly (router or Pi-hole config)
*.kagiso.me  A  10.0.10.110
```

When on the LAN or connected via WireGuard, hostnames resolve to `10.0.10.110` (Traefik) directly, bypassing Cloudflare.

Adding a new public-facing service requires:
1. Creating an `IngressRoute` or `Ingress` resource with the desired hostname.
2. Adding a proxied CNAME record in Cloudflare DNS pointing to the tunnel.
3. Adding a hostname rule to the Cloudflare Tunnel configuration.

---

## TLS Architecture

Public TLS is handled automatically by Cloudflare at the edge. cert-manager remains in the cluster for internal CA use and for Let's Encrypt certificates used by direct/VPN access paths (e.g., Plex over WireGuard).

**Issuers:**

| Issuer | Type | Use case |
|--------|------|---------|
| `letsencrypt` | ACME HTTP-01 | Direct/VPN access (e.g., Plex via WireGuard) |
| `internal-ca` | Self-signed | Internal services with no external exposure |
| Cloudflare edge TLS | Managed by Cloudflare | All public web services (automatic, no config required) |

**Certificate flow — public services (Cloudflare Tunnel):**

```
Browser connects to Cloudflare Edge
  │
  ▼
Cloudflare terminates TLS automatically (managed certificate)
  │
  ▼
Encrypted tunnel to cloudflared → Traefik (internal plain or TLS)
  │
  ▼
No cert-manager involvement for public TLS
```

**Certificate flow — direct/VPN access (e.g., Plex via WireGuard):**

```
IngressRoute / Ingress resource created
  │
  ▼
cert-manager creates CertificateRequest
  │
  ▼
ACME HTTP-01 challenge served by Traefik
  │
  ▼
Let's Encrypt validates challenge
  │
  ▼
Certificate issued → stored as Kubernetes Secret
  │
  ▼
Traefik serves HTTPS using the Secret
  │
  ▼
cert-manager renews 30 days before expiry (automatic)
```

> **Note:** Plex is accessed remotely via WireGuard and uses a Let's Encrypt certificate directly. It does not go through Cloudflare Tunnel due to Cloudflare's ToS prohibition on video streaming proxy.

---

## External Access Architecture

Three access paths serve different use cases:

| Path | Used For | TLS Source | Notes |
|------|----------|-----------|-------|
| Cloudflare Tunnel | All public web services | Cloudflare (automatic) | No open inbound ports required |
| WireGuard VPN | Plex/media streaming, remote admin SSH | Let's Encrypt (cert-manager) | Cloudflare ToS prohibits video proxy |
| Direct LAN | All internal traffic | Internal CA or Let's Encrypt | Bypasses Cloudflare entirely |

### Cloudflare Tunnel — Web Services

Services exposed through Cloudflare Tunnel include: Grafana, Sonarr, Radarr, Nextcloud, Immich UI, and other HTTP-based applications. The tunnel is an outbound connection from `cloudflared` (running on the RPi or Proxmox), so no inbound firewall rules are needed for web traffic.

### WireGuard — Media Streaming and Remote Admin

Plex and any direct media access use WireGuard. Once connected, the client is on the home LAN and accesses services at their internal IPs. Remote SSH to homelab nodes also goes through WireGuard rather than the Cloudflare Tunnel.

### Direct LAN — Internal Traffic

All traffic from devices on the local network goes directly to `10.0.10.110` (Traefik) via MetalLB, bypassing Cloudflare entirely. Internal DNS resolves `*.kagiso.me` to `10.0.10.110`.

---

## Kubernetes Internal Networking

| Component | CIDR | Notes |
|-----------|------|-------|
| Pod network (flannel) | 10.42.0.0/16 | k3s default |
| Service ClusterIP network | 10.43.0.0/16 | k3s default |
| Node network | 10.0.10.0/24 | Physical network |
| MetalLB pool | 10.0.10.110/28 | Subset of node network |

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
| 51820 | UDP | WireGuard (if used) |
| 443 | TCP | HTTPS ingress (all nodes, MetalLB) |
| 80 | TCP | HTTP ingress (internal redirect; no longer used for public ACME challenge) |

---

## Related Guides

- [Guide 03: Networking Platform](../03-Networking-Platform.md)
- [ADR-003: Traefik over nginx-ingress](./decisions/ADR-003-traefik-over-nginx-ingress.md)
