# Raspberry Pi — Dedicated Appliance (bran)

**Hostname:** `bran`
**IP:** `10.0.10.10` (transitioning — will be reassigned a new static IP once varys takes over as control hub)
**OS:** Raspberry Pi OS Lite (64-bit, Debian Bookworm)
**Hardware:** Raspberry Pi 3B+

---

## Role

Bran is a **dedicated network appliance** — not a management or control node. It handles three persistent services that benefit from being on a low-power, always-on device.

| Service | Purpose |
|---------|---------|
| **Pi-hole** | Secondary DNS server — redundant ad blocking and LAN DNS resolution |
| **Tailscale exit node** | WireGuard-based remote access and exit node for the homelab network |
| **WOL proxy** | Wake-on-LAN proxy for nodes that don't support remote wake-up from WAN |

The **control hub role** (kubectl, flux, Ansible, GitHub runner, Grafana, Alertmanager, cloudflared) has moved to **varys** — see [../README.md](../README.md).

---

## Services Running on bran

### Pi-hole (Secondary DNS)

The primary Pi-hole runs on varys (`10.0.10.10`). Bran runs a secondary Pi-hole instance as a fallback DNS server, handed out as DNS Server 2 by the DHCP server.

```
UniFi Controller → Networks → [LAN] → DHCP → DNS Server 2: <bran-ip>
```

### Tailscale Exit Node

Bran acts as the Tailscale exit node for the homelab network, enabling remote access to all LAN services without requiring an open inbound port on the router.

```bash
# Enable exit node on bran (run once after Tailscale install)
sudo tailscale up --advertise-exit-node --advertise-routes=10.0.10.0/24
```

### WOL Proxy

Bran's LAN presence allows it to send Wake-on-LAN magic packets to hosts that can't be reached from WAN directly.

```bash
# Wake a host by MAC address
wakeonlan <MAC_ADDRESS>
```

---

## Access

```bash
# SSH to bran (from LAN or via Tailscale)
ssh kagiso@<bran-ip>
```

Bran is not a jump host. Access it directly for appliance management only.

---

## Directory Structure

```
raspberry-pi/
├── README.md               # this file
├── ansible/
│   ├── ansible.cfg
│   ├── inventory/
│   │   └── hosts.yml       # bran host definition
│   └── playbooks/
│       └── setup.yml       # bran bootstrap (Pi-hole, Tailscale, WOL)
└── docs/
    └── setup.md            # setup walkthrough
```
