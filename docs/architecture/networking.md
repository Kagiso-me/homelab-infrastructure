
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

## Traffic Flow — HTTP/HTTPS Request

```
User (browser)
  │
  ▼
DNS query: grafana.kagiso.me
  │
  ▼
DNS record: *.kagiso.me → 10.0.10.110  (or per-service CNAME/A records)
  │
  ▼
MetalLB (ARP response for 10.0.10.110)
  │
  ▼
Cluster node (running MetalLB speaker)
  │
  ▼
Traefik Service (ClusterIP, via kube-proxy)
  │
  ▼
Traefik pod (TLS termination, host matching)
  │
  ▼
Application Service (ClusterIP)
  │
  ▼
Application pod
```

---

## DNS Architecture

All cluster services are accessed via hostnames under `kagiso.me` (public domain).

**DNS configuration** (managed in your DNS provider):

```
# Option 1 — wildcard (routes all *.kagiso.me to Traefik)
*.kagiso.me  A  10.0.10.110

# Option 2 — per-service records (more explicit, same effect)
grafana.kagiso.me  A  10.0.10.110
```

Because `kagiso.me` is a publicly registered domain, Let's Encrypt HTTP-01 challenges work without any special configuration. Traefik serves the ACME challenge response, Let's Encrypt validates it, and a trusted certificate is issued.

Adding a new application requires:
1. Creating an `IngressRoute` or `Ingress` resource with the desired hostname.
2. Adding a DNS A/CNAME record pointing to `10.0.10.110` (or covered by wildcard).

---

## TLS Architecture

TLS termination occurs at Traefik. cert-manager manages certificate lifecycle.

**Issuers:**

| Issuer | Type | Use case |
|--------|------|---------|
| `letsencrypt-staging` | ACME HTTP-01 | Testing (untrusted certs) |
| `letsencrypt-prod` | ACME HTTP-01 | Production (trusted certs) |
| `internal-ca` | Self-signed | Internal services with no external exposure |

**Certificate flow:**

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
| 80 | TCP | HTTP ingress / ACME challenge |

---

## Related Guides

- [Guide 03: Networking Platform](../03-Networking-Platform.md)
- [ADR-003: Traefik over nginx-ingress](./decisions/ADR-003-traefik-over-nginx-ingress.md)
