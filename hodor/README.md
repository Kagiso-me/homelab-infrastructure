# hodor — Observer / DNS

**Hostname:** `hodor`
**IP:** `10.0.10.9` (static, reserved via UniFi DHCP)
**OS:** Raspberry Pi OS Lite (64-bit, Debian Bookworm)
**Hardware:** Raspberry Pi

---

## The Character

<div align="center">

<!-- Photo placeholder: Hodor (Kristian Nairn) from Game of Thrones -->
> _📸 Photo coming soon — Hodor_

</div>

**Hodor** is Bran Stark's gentle giant — a man of few words (in fact, just one) who does exactly one job, does it reliably, and does it without complaint. His entire existence is defined by a single, critical purpose: *hold the door*. He keeps threats out and keeps the household safe, no matter what.

**Why this machine:** `hodor` holds the door for the entire homelab network. It runs Pi-hole (DNS) and Unbound — the two services everything else depends on for network resolution. No DNS means no homelab. It's a small, always-on Raspberry Pi that does one job perfectly and never gets in the way. Simple. Reliable. Unwavering.

---

## Role

hodor is a **dedicated network appliance** — always-on, low-power, independent of the Kubernetes cluster and the control hub (varys). It runs services that the rest of the homelab depends on, so they must not share fate with anything else.

| Service | Purpose |
|---------|---------|
| **Pi-hole** | Primary DNS server — network-wide ad blocking and split DNS for `*.kagiso.me` and `*.local.kagiso.me` |
| **Unbound** | Recursive DNS resolver — upstream for Pi-hole, fully self-contained (no third-party DNS) |
| **Tailscale exit node** | WireGuard-based remote access and LAN route advertisement |
| **WOL proxy** | Wake-on-LAN proxy for nodes that can't be woken remotely |

---

## Why a Dedicated Node for DNS

Pi-hole is the single most critical network service — every LAN device depends on it for DNS resolution. Keeping it on a dedicated RPi ensures:

- A Kubernetes failure, varys maintenance, or heavy Ansible run does not affect DNS.
- The RPi draws ~3–5W idle — always-on cost is negligible.
- A second Pi-hole (e.g. on varys) can be added as DNS Server 2 for redundancy without changing the primary.

---

## DNS Architecture

hodor provides two wildcard DNS entries that cover all homelab services:

| Wildcard | Resolves To | Covers |
|----------|-------------|--------|
| `*.kagiso.me` | `10.0.10.110` | External Traefik — public-facing apps |
| `*.local.kagiso.me` | `10.0.10.111` | Internal Traefik — LAN-only apps and admin tools |

All upstream DNS queries are handled recursively by Unbound (no forwarding to Cloudflare/Google). DNSSEC is validated at the Unbound layer.

---

## Services

### Pi-hole (Primary DNS)

Network-wide DNS server and ad blocker. All LAN devices use hodor as DNS Server 1 via UniFi DHCP.

- Admin UI: `http://10.0.10.15/admin`
- Blocklists: oisd big, hagezi Pro, hagezi Threat Intelligence Feeds
- Upstream: Unbound at `127.0.0.1#5335`

See [docs/01_pihole.md](docs/01_pihole.md) for full setup and configuration guide.

### Unbound (Recursive Resolver)

Recursive DNS resolver that handles all upstream queries for Pi-hole. Queries root nameservers directly — no third-party DNS provider involved.

- Listens on: `127.0.0.1:5335`
- DNSSEC validation enabled
- QNAME minimisation enabled (privacy)

See [docs/02_unbound.md](docs/02_unbound.md) for full setup guide.

### Tailscale Exit Node

hodor acts as the Tailscale exit node for the homelab network, enabling remote access to all LAN services and advertising the `10.0.10.0/24` route.

```bash
# Enable exit node on hodor (run once after Tailscale install)
sudo tailscale up --advertise-exit-node --advertise-routes=10.0.10.0/24
```

### WOL Proxy

hodor's permanent LAN presence allows it to send Wake-on-LAN magic packets to hosts that can't be reached from WAN directly.

```bash
# Wake a host by MAC address
wakeonlan <MAC_ADDRESS>
```

---

## Access

```bash
# SSH to hodor (from LAN or via Tailscale)
ssh kagiso@10.0.10.15
```

hodor is an appliance node — SSH for maintenance only, not a general-purpose shell host.

---

## Directory Structure

```
hodor/
├── README.md               # this file
├── ansible/
│   ├── ansible.cfg
│   ├── inventory/
│   │   └── hosts.yml       # hodor host definition
│   └── playbooks/
│       └── setup.yml       # hodor bootstrap (Pi-hole, Unbound, Tailscale, WOL)
└── docs/
    ├── 01_pihole.md        # Pi-hole setup and configuration
    └── 02_unbound.md       # Unbound recursive resolver setup
```

---

## Related

- [ADR-014: Pi-hole + Unbound DNS Architecture](../docs/adr/ADR-014-pihole-unbound-dns.md)
- [Architecture: Networking](../docs/architecture/networking.md)
