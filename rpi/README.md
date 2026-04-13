# bran — Observer / DNS

**Hostname:** `bran`
**IP:** `10.0.10.9` (static, reserved via UniFi DHCP)
**OS:** Raspberry Pi OS Lite (64-bit, Debian Bookworm)
**Hardware:** Raspberry Pi

---

## The Character

<div align="center">

<!-- Photo placeholder: Bran Stark (Isaac Hempstead Wright) from Game of Thrones -->
> _📸 Photo coming soon — Bran Stark_

</div>

**Bran Stark** — *The Three-Eyed Raven* — is gifted with greensight: the ability to see across time and across all corners of the world simultaneously. He doesn't act directly or fight battles. Instead, he watches, knows, and sees everything that happens everywhere in the realm. No event escapes him.

**Why this machine:** `bran` observes the homelab network — watching the cluster, running the status pipeline, monitoring services, and keeping CI execution off the privileged control hub. Like the character, bran doesn't do the work itself. It watches, reports, and runs the jobs that keep everything else moving.

---

## Role

bran is a **dedicated observer / CI node** — always-on, low-power, independent of the Kubernetes cluster and the control hub (varys). It runs services that are kept off the privileged control hub.

| Service | Purpose |
|---------|---------|
| **GitHub Actions runners** | CI execution for homelab-infrastructure and kagiso.me — isolated from varys |
| **Tailscale exit node** | WireGuard-based remote access and LAN route advertisement |
| **WOL proxy** | Wake-on-LAN proxy for nodes that can't be woken remotely |

---

## Why bran and not varys

varys holds the age key, kubeconfig, and SSH keys to all nodes — too privileged to expose to GitHub-facing processes. bran is low-privilege, always-on, and the correct host for CI execution. If bran is compromised, blast radius is contained.

---

## Services

### GitHub Actions Runners

Three runners are registered on bran for CI workloads:

| Directory | Workflow scope | Label |
|-----------|---------------|-------|
| `~/actions-runner-site/` | kagiso.me site | `bran-site` |
| `~/actions-runner-k3s/` | homelab-infrastructure (validate + health) | `bran-k3s` |
| `~/actions-runner-docker/` | homelab-infrastructure (docker-deploy) | `bran-docker` |

### Tailscale Exit Node

bran acts as the Tailscale exit node for the homelab network, enabling remote access to all LAN services and advertising the `10.0.10.0/24` route.

```bash
# Enable exit node on bran (run once after Tailscale install)
sudo tailscale up --advertise-exit-node --advertise-routes=10.0.10.0/24
```

### WOL Proxy

bran's permanent LAN presence allows it to send Wake-on-LAN magic packets to hosts that can't be reached from WAN directly.

```bash
# Wake a host by MAC address
wakeonlan <MAC_ADDRESS>
```

---

## Access

```bash
# SSH to bran (from LAN or via Tailscale)
ssh kagiso@10.0.10.9
```

bran is a low-privilege node — SSH for maintenance only, not a general-purpose shell host.

---

## Directory Structure

```
bran/
├── README.md               # this file
├── ansible/
│   ├── ansible.cfg
│   ├── inventory/
│   │   └── hosts.yml       # bran host definition
│   └── playbooks/
│       └── setup.yml       # bran bootstrap (Tailscale, WOL, runners)
└── docs/
    └── 01_tailscale.md     # Tailscale exit node setup (if exists)
```

---

## Related

- [ADR-018: MikroTik Adblock + Static DNS](../docs/adr/ADR-018-mikrotik-adblock-static-dns.md)
- [Architecture: Networking](../docs/architecture/networking.md)
