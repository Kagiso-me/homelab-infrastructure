# ADR-014 — MetalLB in L2 Mode for Bare-Metal Load Balancing

**Status:** Accepted
**Date:** 2026-01-15
**Deciders:** Kagiso

---

## Context

Kubernetes `LoadBalancer` services require an external load balancer to assign a real IP
address. In cloud environments this is provided automatically (AWS ELB, GCP LB, etc.).
On bare metal, without an explicit solution, `LoadBalancer` services stay in `<pending>`
indefinitely and are functionally equivalent to `ClusterIP`.

The platform needs Traefik to be reachable at a stable LAN IP so that:
- All HTTP/HTTPS ingress routes through a single point
- The IP does not change when the Traefik pod reschedules
- Services can be reached from the LAN without NodePort hackery

Three approaches were evaluated:

1. **MetalLB** — a bare-metal load balancer that assigns LAN IPs to `LoadBalancer` services
2. **NodePort** — expose services on a fixed port on every node's IP
3. **Host network + static IP** — run Traefik with `hostNetwork: true` on a pinned node

---

## Decision

**MetalLB in L2 (ARP) mode**, with an IP pool of `10.0.10.110–10.0.10.115`.

---

## Rationale

### MetalLB over NodePort

NodePort exposes a service on a high port (30000–32767) on every node. This has two problems:

1. **No standard ports.** HTTPS on `10.0.10.10:32443` is not the same as HTTPS on
   `10.0.10.110:443`. Browser clients, cert validation, and DNS all assume standard ports.
   Workaround (iptables rules to redirect 443 → NodePort) adds fragile host-level state
   that is not managed by Kubernetes and disappears on node reboot.

2. **Node-coupled.** Traffic reaches whichever node the client happens to hit — if that
   node's Traefik pod is not ready, the connection fails even if other nodes are healthy.
   MetalLB assigns the VIP to the node currently running the elected pod and moves it on
   rescheduling, naturally following the workload.

### MetalLB over host network

Running Traefik with `hostNetwork: true` pinned to one node gives it port 80/443 on that
node's IP. This works but has two problems:

1. **Node failure = ingress failure.** If the pinned node goes down, Traefik goes with it.
   There is no automatic failover without additional tooling.

2. **Unmanaged coupling.** The service IP is the node's IP, not a virtual IP. If the node
   is replaced, the IP changes and DNS must be updated. MetalLB's VIP is decoupled from
   any specific node — it moves automatically.

### L2 mode over BGP mode

MetalLB supports BGP mode for production-grade anycast load balancing across multiple nodes.
BGP requires a router that speaks BGP (e.g. a MikroTik or pfSense with BGP configured).

The homelab LAN uses a MikroTik router but BGP configuration adds significant complexity
for marginal benefit at this scale. L2 mode uses ARP — MetalLB elects one node to hold
the VIP and responds to ARP requests for it. Failover is handled by re-election when the
holding node goes down, with a brief interruption (seconds, not minutes).

For a three-node homelab cluster where full HA is best-effort rather than contractual,
L2 mode's simplicity outweighs BGP's multi-node load distribution benefit.

---

## IP Pool

`10.0.10.110–10.0.10.115` — six addresses reserved in the DHCP server's excluded range
so they are never assigned dynamically. Current allocations:

| IP | Service |
|----|---------|
| 10.0.10.110 | Traefik (external — internet-facing ingress) |
| 10.0.10.111 | Traefik (internal — LAN-only ingress) |
| 10.0.10.112–115 | Reserved for future services |

---

## Consequences

- `LoadBalancer` services get real LAN IPs, reachable at standard ports
- Traefik's IP is stable across pod reschedules and node failures
- L2 mode means one node holds the VIP at a time — a node failure causes a brief (~5s) ARP re-election before traffic resumes
- The IP pool must be kept out of the DHCP range to avoid conflicts — this is a manual configuration on the MikroTik router
- Adding new `LoadBalancer` services consumes pool IPs — the pool is intentionally small to force explicit allocation decisions
