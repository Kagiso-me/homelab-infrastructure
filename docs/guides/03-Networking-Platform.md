
# 03 — Networking Platform (MetalLB + Traefik + DNS + TLS)
## Exposing Services from the Cluster

**Author:** Kagiso Tjeane
**Difficulty:** ⭐⭐⭐⭐⭐⭐⭐☆☆☆ (7/10)
**Guide:** 03 of 12

> Kubernetes clusters running on bare-metal do not provide built‑in load balancers or ingress gateways.
>
> This phase introduces the **networking platform** responsible for exposing cluster services to the network
> in a predictable, production‑style way.
>
> MetalLB, cert-manager, and Traefik are installed by a **single Ansible playbook** that handles
> ordering, dependency waits, and post-install verification automatically. Cloudflare Tunnel and
> Tailscale are separate setup steps covered later in this guide.

The networking layer consists of:

- **MetalLB** — provides LoadBalancer IP addresses on bare metal
- **Traefik** — ingress controller handling HTTP/S routing
- **Wildcard DNS** — human-friendly service hostnames
- **cert-manager** — internal CA (`internal-ca` ClusterIssuer) for cluster-internal TLS
- **Cloudflare Tunnel** — outbound tunnel for public service exposure (no open inbound ports)
- **Tailscale / Headscale** — encrypted private access for Plex, SSH, and kubectl

Together these components transform a raw Kubernetes cluster into a **usable application platform**.

---

## Table of Contents

1. [Why a Networking Layer Is Required](#why-a-networking-layer-is-required)
2. [Full Networking Architecture](#full-networking-architecture)
3. [Component Overview](#component-overview)
4. [Prerequisites](#prerequisites)
5. [Installation — Ansible Playbook](#installation--ansible-playbook)
6. [What the Playbook Does](#what-the-playbook-does)
7. [DNS Configuration](#dns-configuration)
8. [Cloudflare Tunnel Setup](#cloudflare-tunnel-setup)
9. [Tailscale / Headscale (Private Remote Access)](#tailscale--headscale-private-remote-access)
10. [TLS Certificate Flow](#tls-certificate-flow)
11. [Ingress vs IngressRoute](#ingress-vs-ingressroute)
12. [Verifying the Platform](#verifying-the-platform)
13. [Exit Criteria](#exit-criteria)
14. [Troubleshooting](#troubleshooting)

---

## Why a Networking Layer Is Required

In cloud environments Kubernetes automatically provisions load balancers:

```
AWS   → Elastic Load Balancer
GCP   → Cloud Load Balancer
Azure → Azure Load Balancer
```

Bare‑metal clusters lack this functionality. Without a networking platform, services appear like this:

```
kubectl get svc

NAME       TYPE           CLUSTER-IP     EXTERNAL-IP   PORT(S)
grafana    LoadBalancer   10.96.44.12    <pending>     80:31234/TCP
```

`<pending>` means no external IP was ever assigned — the service is unreachable from outside the cluster.

MetalLB solves this problem by allowing Kubernetes to allocate real IP addresses from the local network
and advertising them using ARP (Layer-2 mode), making the cluster appear to "own" those IPs to the rest
of the LAN.

---

## Full Networking Architecture

```mermaid
graph TD
    Browser["Browser"] -->|"HTTPS (public)"| CF["Cloudflare Edge<br/>TLS terminated here"]
    CF -->|"Encrypted tunnel"| CFD["cloudflared daemon<br/>(RPi — 10.0.10.10)"]
    CFD --> Traefik["Traefik Ingress Controller<br/>Host-based routing"]
    Traefik -->|"Host: grafana.kagiso.me"| Grafana["Grafana Service"]
    Traefik -->|"Host: app.kagiso.me"| App["Other App Services"]
    CertManager["cert-manager<br/>internal-ca ClusterIssuer only"] -.->|issues internal TLS Secrets| Traefik
    TS["Tailscale Client<br/>(Plex / SSH / kubectl)"] -->|"Encrypted peer-to-peer tunnel"| Traefik
```

Traffic flows from the browser through Cloudflare Edge → cloudflared tunnel → Traefik → the target service. Cloudflare handles public TLS automatically. For private remote access (Plex, SSH, kubectl), Tailscale provides encrypted peer-to-peer tunnels with its own certificate infrastructure. cert-manager is retained only for the `internal-ca` ClusterIssuer used by internal cluster services.

---

## Component Overview

| Component | Version | Namespace | Responsibility |
|-----------|---------|-----------|----------------|
| MetalLB | v0.14.5 | `metallb-system` | Assign LoadBalancer IPs from the local IP pool |
| cert-manager | v1.14.4 | `cert-manager` | Internal CA (`internal-ca` ClusterIssuer) for cluster-internal TLS only. No Let's Encrypt issuers deployed. |
| Traefik | 28.x | `traefik` | HTTP/S routing, TLS termination, IngressRoute CRDs |

### MetalLB — Layer-2 Mode

MetalLB operates in Layer-2 (ARP) mode for this homelab. A Speaker pod on each node listens for
ARP requests and claims ownership of addresses in the pool:

```
Client sends ARP: "Who owns 10.0.10.110?"
MetalLB Speaker responds: "I do" (node MAC address)
Traffic routed to that node → kube-proxy → Traefik pod
```

**IP pool:** `10.0.10.110 – 10.0.10.125` (21 addresses available for LoadBalancer services)
**Traefik pinned to:** `10.0.10.110`

### cert-manager — Internal CA Only

cert-manager is retained for the `internal-ca` ClusterIssuer only. It issues certificates for internal cluster services that have no external exposure.

**No Let's Encrypt issuers are deployed.** The three TLS paths are:

- **Public TLS** → Cloudflare. TLS is terminated at the Cloudflare Edge automatically for all services routed through Cloudflare Tunnel. No cert-manager involvement.
- **Private access TLS** → Tailscale. Plex, SSH, and kubectl remote access use Tailscale's own encrypted tunnels and certificate infrastructure. No cert-manager or Let's Encrypt involvement.
- **Internal cluster TLS** → `internal-ca`. cert-manager issues certificates signed by the internal CA for services that communicate internally and require TLS within the cluster.

### Traefik — Ingress Controller

Traefik is the single entry point for all HTTP/S traffic. It:

- Listens on port 80 and 443 at `10.0.10.110`
- Redirects all HTTP → HTTPS automatically
- Routes requests to the correct backend Service based on the `Host` header
- Serves TLS certificates stored as Kubernetes Secrets by cert-manager

---

## Prerequisites

Before running the platform playbook:

| Requirement | Check |
|-------------|-------|
| k3s cluster running | `kubectl get nodes` — all nodes Ready |
| Ansible installed on RPi | `ansible --version` |
| RPi can SSH to tywin (10.0.10.11) | `ssh kagiso@10.0.10.11` |
| DNS wildcard configured | `*.kagiso.me → 10.0.10.110` in your internal DNS server (Pi-hole/router) |

> **DNS note:** Internal DNS (Pi-hole or router) should point `*.kagiso.me` to `10.0.10.110` for
> LAN and Tailscale access. MetalLB and Traefik provide the LoadBalancer IP and ingress routing
> for LAN-accessible services. Cloudflare Tunnel setup is a separate step — see the
> [Cloudflare Tunnel Setup](#cloudflare-tunnel-setup) section below.

---

## Installation — Ansible Playbook

The entire networking platform is installed by a single playbook from the Raspberry Pi control hub:

```bash
# From the Raspberry Pi (10.0.10.10)
ansible-playbook -i ansible/inventory/homelab.yml \
  ansible/playbooks/lifecycle/install-platform.yml
```

**Playbook location:** [`ansible/playbooks/lifecycle/install-platform.yml`](../../ansible/playbooks/lifecycle/install-platform.yml)

To install only a specific component (using tags):

```bash
# MetalLB only
ansible-playbook ... --tags metallb

# cert-manager only
ansible-playbook ... --tags cert-manager

# Traefik only
ansible-playbook ... --tags traefik
```

To override defaults (e.g., for a different email or IP range):

```bash
ansible-playbook ... \
  -e metallb_ip_range=10.0.10.110-10.0.10.125 \
  -e traefik_loadbalancer_ip=10.0.10.110
```

---

## What the Playbook Does

The playbook runs on the k3s control plane node (`tywin`) in strict dependency order:

```mermaid
sequenceDiagram
    participant RPi as Raspberry Pi (ansible)
    participant CP as tywin (control plane)
    participant K8s as Kubernetes API

    RPi->>CP: SSH connection
    CP->>K8s: Pre-flight: verify all nodes Ready
    CP->>K8s: Install Helm (if absent)

    Note over CP,K8s: Step 1 — MetalLB
    CP->>K8s: kubectl apply metallb-native.yaml
    CP->>K8s: Wait for controller + speaker rollout
    CP->>K8s: Apply IPAddressPool + L2Advertisement

    Note over CP,K8s: Step 2 — cert-manager
    CP->>K8s: kubectl apply cert-manager CRDs
    CP->>K8s: helm install cert-manager
    CP->>K8s: Wait for webhook rollout
    CP->>K8s: Apply internal-ca ClusterIssuer

    Note over CP,K8s: Step 3 — Traefik
    CP->>K8s: helm install traefik (loadBalancerIP: 10.0.10.110)
    CP->>K8s: Wait for deployment rollout
    CP->>K8s: Assert LoadBalancer IP == 10.0.10.110

    CP->>RPi: Print final pod status + Traefik IP
```

The playbook performs explicit waits after each rollout and asserts that Traefik received the
expected LoadBalancer IP from MetalLB before completing.

---

## DNS Configuration

There are two DNS layers: Cloudflare (public) and internal DNS (LAN/Tailscale).

### Cloudflare DNS — Public access

Public services use proxied CNAME records in Cloudflare, pointing to the Cloudflare Tunnel:

| Record | Type | Value | Proxy |
|--------|------|-------|-------|
| `grafana.kagiso.me` | CNAME | `<tunnel-id>.cfargotunnel.com` | Proxied (orange cloud) |
| `nextcloud.kagiso.me` | CNAME | `<tunnel-id>.cfargotunnel.com` | Proxied (orange cloud) |
| `immich.kagiso.me` | CNAME | `<tunnel-id>.cfargotunnel.com` | Proxied (orange cloud) |

With Cloudflare proxying enabled, external clients resolve to Cloudflare's anycast IPs — the home network IP is never exposed publicly.

### Internal DNS — LAN and Tailscale access

Configure a wildcard record on the internal DNS server (Pi-hole or router):

| Record | Type | Value |
|--------|------|-------|
| `*.kagiso.me` | A | `10.0.10.110` |

This routes all internal hostnames directly to Traefik, bypassing Cloudflare. New services added to Kubernetes are immediately reachable on the LAN without DNS changes — only a new IngressRoute is required. When connected via Tailscale, the same wildcard resolves to `10.0.10.110` if the internal DNS server is set as the Tailscale DNS resolver.

---

## Cloudflare Tunnel Setup

Cloudflare Tunnel (`cloudflared`) creates an outbound encrypted connection from the homelab to Cloudflare's edge. No inbound ports need to be opened on the router or firewall — the tunnel is initiated from inside the network.

**How it works:** `cloudflared` on the RPi establishes persistent outbound connections to Cloudflare's edge. When a request arrives at `grafana.kagiso.me`, Cloudflare routes it through the tunnel to `cloudflared`, which forwards it to Traefik at `10.0.10.110`. Traefik matches the `Host` header and routes to the correct backend service.

### Installation on RPi (armv7l)

```bash
# On the Raspberry Pi (10.0.10.10)
curl -L --output cloudflared.deb \
  https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-arm.deb
sudo dpkg -i cloudflared.deb
cloudflared --version
```

### Authenticate and Create Tunnel

```bash
cloudflared tunnel login
cloudflared tunnel create homelab
```

`tunnel login` opens a browser to authenticate with Cloudflare. `tunnel create` registers the tunnel and writes the credentials file to `~/.cloudflared/`.

### Config File

Create `/etc/cloudflared/config.yml`:

```yaml
tunnel: <tunnel-id>
credentials-file: /root/.cloudflared/<tunnel-id>.json
ingress:
  - hostname: grafana.kagiso.me
    service: http://10.0.10.110
    originRequest:
      httpHostHeader: grafana.kagiso.me
  - hostname: sonarr.kagiso.me
    service: http://10.0.10.110
    originRequest:
      httpHostHeader: sonarr.kagiso.me
  - service: http_status:404
```

The `httpHostHeader` ensures Traefik receives the original hostname and routes to the correct backend. The catch-all `http_status:404` at the end is required — `cloudflared` rejects configs without a final catch-all rule.

### Route DNS and Install as Service

```bash
cloudflared tunnel route dns homelab grafana.kagiso.me
cloudflared tunnel route dns homelab sonarr.kagiso.me
sudo cloudflared service install
sudo systemctl enable --now cloudflared
```

`tunnel route dns` creates the proxied CNAME record in Cloudflare DNS automatically.

### Adding a New Service

Adding a new public service only requires adding an ingress rule to `/etc/cloudflared/config.yml` and restarting `cloudflared`. No Cloudflare dashboard changes are needed if using tunnel DNS routing:

```bash
# Add rule to config.yml, then:
sudo systemctl restart cloudflared
# Run once to create the DNS record:
cloudflared tunnel route dns homelab newservice.kagiso.me
```

> **Plex / media streaming:** Do NOT route Plex through Cloudflare Tunnel. Cloudflare's ToS prohibits proxying video streaming. Use Tailscale instead (see next section).

---

## Tailscale / Headscale (Private Remote Access)

The access model is split by service type:

- **Public web services** (Grafana, Sonarr, Nextcloud, etc.) → Cloudflare Tunnel
- **Private services** (Plex, SSH, kubectl) → Tailscale

Tailscale creates encrypted WireGuard-based peer-to-peer tunnels between devices. Devices enrolled in the same Tailscale network can reach each other directly using Tailscale IPs or MagicDNS hostnames.

### Install Tailscale on RPi and Nodes

```bash
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up
```

Run this on each device that needs remote access (RPi, workstation, phone, etc.). After `tailscale up`, each device gets a stable Tailscale IP (100.x.x.x range).

### Accessing Plex via Tailscale

Once enrolled, access Plex directly using its Tailscale IP or via MagicDNS:

```
# Direct by Tailscale IP
http://100.x.x.x:32400/web

# Via MagicDNS (if enabled in Tailscale admin)
http://plex-host.tail<network>.ts.net:32400/web
```

No Traefik IngressRoute is required for Tailscale-only services — clients connect directly to the host running the service.

### SSH and kubectl via Tailscale

```bash
# SSH to a homelab node over Tailscale
ssh kagiso@100.x.x.x

# kubectl via Tailscale (after adding Tailscale IP to kubeconfig)
kubectl --server=https://100.x.x.x:6443 get nodes
```

### Headscale — Self-Hosted Coordination Server

[Headscale](https://headscale.net/) is a self-hosted alternative to the Tailscale coordination server. Running Headscale as an LXC container on Proxmox removes the dependency on Tailscale's hosted service. This is a planned future enhancement for this homelab.

> **TLS note:** Tailscale handles its own certificate infrastructure for MagicDNS and HTTPS. No cert-manager configuration or Let's Encrypt setup is required for Tailscale-connected services.

---

## TLS Certificate Flow

TLS is handled by three separate systems. No Let's Encrypt issuers are deployed in the cluster.

**Public TLS → Cloudflare.** All services routed through Cloudflare Tunnel have TLS terminated automatically at the Cloudflare Edge. Cloudflare manages the certificate lifecycle with no cluster-side configuration required. No ClusterIssuer annotation is needed on IngressRoutes served via the tunnel.

**Private access TLS → Tailscale.** Plex, SSH, and remote `kubectl` access use Tailscale's encrypted peer-to-peer tunnels. Tailscale handles its own certificate infrastructure. No cert-manager or Let's Encrypt configuration is required for these access paths.

**Internal cluster TLS → `internal-ca`.** cert-manager is retained for the `internal-ca` ClusterIssuer, which signs certificates for services that communicate internally and require TLS within the cluster. IngressRoutes for internal-only services may reference this issuer:

```yaml
apiVersion: traefik.io/v1alpha1
kind: IngressRoute
metadata:
  name: internal-service
  annotations:
    cert-manager.io/cluster-issuer: internal-ca
spec:
  entryPoints: [websecure]
  routes:
    - match: Host(`internal-service.kagiso.me`)
      kind: Rule
      services:
        - name: internal-service
          port: 8080
  tls:
    secretName: internal-service-tls
```

---

## Ingress vs IngressRoute

Traefik supports two routing models:

### Standard Kubernetes Ingress

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: grafana
spec:
  ingressClassName: traefik
  rules:
    - host: grafana.kagiso.me
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: grafana
                port:
                  number: 3000
```

- Portable across ingress controllers
- Limited to basic path/host routing
- No middleware support without annotations

### Traefik IngressRoute (Recommended)

```yaml
apiVersion: traefik.io/v1alpha1
kind: IngressRoute
metadata:
  name: grafana
spec:
  entryPoints: [websecure]
  routes:
    - match: Host(`grafana.kagiso.me`)
      kind: Rule
      middlewares:
        - name: secure-headers
      services:
        - name: grafana
          port: 3000
  tls:
    secretName: grafana-tls
```

- Full Traefik routing rule syntax
- Middleware support (auth, rate limiting, headers)
- Better observability via Traefik dashboard

**All homelab services use IngressRoute.** The pattern is established in
[`apps/base/grafana/`](../../apps/base/grafana/) and followed by all subsequent applications.

---

## Verifying the Platform

After the playbook completes, run these checks from the RPi:

```bash
# MetalLB — controller and speakers running
kubectl get pods -n metallb-system
# Expected: metallb-controller (1/1) and metallb-speaker (1/1 per node)

# MetalLB — IP pool configured
kubectl get ipaddresspool -n metallb-system
# Expected: homelab-pool with 10.0.10.110-10.0.10.125

# cert-manager — all pods running
kubectl get pods -n cert-manager
# Expected: cert-manager, cert-manager-cainjector, cert-manager-webhook (all 1/1)

# cert-manager — ClusterIssuer ready
kubectl get clusterissuer
# Expected: internal-ca READY=True

# Traefik — running and assigned LoadBalancer IP
kubectl get svc -n traefik
# Expected: traefik TYPE=LoadBalancer EXTERNAL-IP=10.0.10.110

# End-to-end — Traefik is responding (expect 404, not connection refused)
curl -k https://10.0.10.110
# Expected: 404 page not found
```

The `404 page not found` response from Traefik is correct — it means Traefik is running and
handling requests, but no IngressRoute has been defined yet to route them anywhere.

---

## Exit Criteria

The networking platform is complete when all of the following are true:

- ✓ `kubectl get pods -n metallb-system` — all pods Running
- ✓ `kubectl get pods -n cert-manager` — all pods Running
- ✓ `kubectl get pods -n traefik` — pod Running
- ✓ Traefik service shows `EXTERNAL-IP: 10.0.10.110`
- ✓ `kubectl get clusterissuer` — `internal-ca` issuer `READY=True`
- ✓ `curl -k https://10.0.10.110` returns `404 page not found`
- ✓ DNS wildcard `*.kagiso.me` resolves to `10.0.10.110` from a client machine

---

## Troubleshooting

**Traefik `EXTERNAL-IP` stays `<pending>`**

MetalLB did not assign an IP. Check:

```bash
kubectl describe svc traefik -n traefik          # Look for events
kubectl get ipaddresspool -n metallb-system      # Pool must exist
kubectl get pods -n metallb-system               # Speakers must be Running
```

Ensure `10.0.10.110` is within the configured pool range (`10.0.10.110-10.0.10.125`).

**cert-manager ClusterIssuer not Ready**

```bash
kubectl describe clusterissuer internal-ca       # Check Status.Conditions
kubectl logs -n cert-manager deploy/cert-manager # Look for errors
```

Common cause: the cert-manager webhook is not yet ready. Wait for all cert-manager pods to be Running before checking the ClusterIssuer status.

**Certificate stuck in `Pending`**

```bash
kubectl describe certificate <name> -n <namespace>  # Check events
kubectl describe certificaterequest -n <namespace>   # Check issuer reference
```

Ensure the Certificate resource references `internal-ca` as the issuer and that cert-manager pods are healthy. No ACME or HTTP-01 challenges are used — certificates are signed directly by the internal CA.

**Traefik returning 404 for a deployed service**

```bash
kubectl get ingressroute -A                     # Verify the IngressRoute exists
kubectl describe ingressroute <name> -n <ns>    # Check the Host rule
kubectl logs -n traefik deploy/traefik          # Check for routing errors
```

Ensure the `Host()` rule in the IngressRoute matches the requested hostname exactly.

---

## Next Guide

➡ **[04 — GitOps Control Plane (FluxCD)](./04-Flux-GitOps.md)**

The next phase introduces FluxCD, allowing the entire platform to be managed declaratively through Git.

---

## Navigation

| | Guide |
|---|---|
| ← Previous | [02 — Kubernetes Installation](./02-Kubernetes-Installation.md) |
| Current | **03 — Networking Platform** |
| → Next | [04 — GitOps Control Plane](./04-Flux-GitOps.md) |
