# ADR-018: MikroTik Built-in Adblock + Static DNS Replaces Pi-hole

**Status:** Accepted — 2026-04-13
**Deciders:** Kagiso
**Supersedes:** [ADR-011: Pi-hole + Unbound as the Homelab DNS Stack](ADR-011-pihole-unbound-dns.md)

---

## Context

Pi-hole was deployed on `bran` (RPi) as the LAN DNS server for split DNS and network-wide ad blocking (see ADR-011). In practice it proved unreliable:

- Random DNS timeouts with no clear cause, causing intermittent failures across all LAN devices.
- The laptop was occasionally blacklisted without explanation, breaking DNS for the primary workstation.
- Maintaining allowlists and blocklists added ongoing operational overhead.
- A single-node Pi-hole creates a hard dependency — DNS for the entire LAN fails if bran has any issue, unless a redundant instance is also run elsewhere.

The operational cost and instability outweighed the benefits. The MikroTik router already provides a built-in adblock capability, and split DNS for internal services can be handled via static DNS entries on the router — removing the external dependency entirely.

---

## Options Considered

### Option 1: Keep Pi-hole — add a second instance for redundancy

Deploy a second Pi-hole on varys as DNS Server 2 to eliminate the single point of failure.

**Rejected** — doubles the maintenance burden. Root instability issues (timeouts, unexplained blacklisting) are not addressed by redundancy. Two unreliable nodes are worse than one.

### Option 2: Replace Pi-hole with AdGuard Home

AdGuard Home is a more modern alternative with a better UI and more active development.

**Rejected** — still a self-hosted DNS appliance with the same class of failure modes (process crash, RPi instability, update breakage). Does not solve the fundamental reliability concern.

### Option 3: MikroTik built-in adblock + static DNS entries (chosen)

Use the MikroTik router's native adblock feature for network-wide blocking. Use MikroTik static DNS entries for split DNS (`*.kagiso.me` and `*.local.kagiso.me`). Point the router DHCP at itself (`10.0.10.1`) as DNS Server 1.

**Chosen** — the router is the network's most stable device (dedicated hardware, no general-purpose OS churn, no process manager). No additional appliance to maintain. DNS redundancy is trivially achieved by using a public resolver (e.g. `1.1.1.1`) as DNS Server 2.

---

## Decision

Decommission Pi-hole and Unbound on `bran`. Configure the MikroTik router as the LAN DNS server with:

1. **MikroTik built-in adblock** for network-wide ad and tracker blocking.
2. **Static DNS entries** on the MikroTik for split DNS resolution of homelab hostnames.
3. **UniFi DHCP** updated to hand out `10.0.10.1` (MikroTik) as DNS Server 1, `1.1.1.1` as fallback.

---

## DNS Architecture

```
LAN device
  │  (DNS query)
  ▼
MikroTik router (10.0.10.1:53)
  │  Static DNS entries checked first:
  │    *.kagiso.me       → 10.0.10.110  (traefik-external)
  │    *.local.kagiso.me → 10.0.10.111  (traefik-internal)
  │  Adblock domains     → blocked (NXDOMAIN)
  │  All other queries forwarded to upstream (1.1.1.1 / 8.8.8.8)
  ▼
Upstream DNS resolver
```

### Split DNS — Static Entries on MikroTik

| Pattern | IP | Purpose |
|---------|-----|---------|
| `*.kagiso.me` | `10.0.10.110` | External Traefik — public-facing apps |
| `*.local.kagiso.me` | `10.0.10.111` | Internal Traefik — LAN-only apps, admin UIs |

Specific services that require explicit static entries (e.g. Docker/NPM hosts, internal tools not covered by wildcards) are added as individual A records on the MikroTik.

### UniFi DHCP Configuration

```
Settings → Networks → [LAN] → DHCP
  DNS Server 1: 10.0.10.1   (MikroTik — primary, adblock + split DNS)
  DNS Server 2: 1.1.1.1     (Cloudflare — fallback, internet DNS only)
```

---

## Trade-offs

| Concern | Pi-hole (old) | MikroTik (new) |
|---------|--------------|----------------|
| Reliability | Intermittent timeouts, unexplained blacklisting | Router-grade stability, dedicated DNS hardware |
| Redundancy | Required a second instance | `1.1.1.1` fallback covers internet DNS; split DNS lost on router failure (acceptable) |
| Ad blocking | Extensive blocklists, UI-managed | MikroTik built-in adblock (less granular, lower maintenance) |
| DNSSEC | Validated by Unbound | Upstream resolver dependent |
| Recursive resolution | Fully self-contained via Unbound | Forwards to upstream (Cloudflare, Google) |
| Operational overhead | High (list updates, allowlists, process maintenance) | Near-zero |

DNSSEC and fully recursive self-contained resolution are accepted losses. Privacy (not forwarding to a third-party resolver) is also relaxed. The trade is worthwhile given the operational stability gained.

---

## Consequences

- Pi-hole and Unbound are decommissioned on `bran`. `bran`'s DNS role is removed.
- New internal services on `*.local.kagiso.me` require no DNS changes — the MikroTik wildcard static entry covers them.
- New public services on `*.kagiso.me` also require no DNS changes on the LAN.
- Docker and NPM services that need internal DNS entries receive explicit static A records on the MikroTik.
- `bran` retains its other roles: Tailscale exit node, WOL proxy, GitHub Actions runners.

---

## References

- [Architecture: Networking](../architecture/networking.md)
- [ADR-011: Pi-hole + Unbound DNS Architecture (Superseded)](ADR-011-pihole-unbound-dns.md)
