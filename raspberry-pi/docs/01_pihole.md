# Pi-hole — Network-Wide DNS & Ad Blocking

**Host:** `hodor` (Raspberry Pi)
**IP:** `10.0.10.15` (static, assigned via UniFi)
**Role:** Primary DNS server for the homelab LAN

---

## Why Pi-hole on a Dedicated RPi

Pi-hole is the single most important network service — every device depends on it for DNS. Running it on a dedicated, always-on Raspberry Pi has clear advantages:

- **Separation of concerns** — DNS is not co-located with the control hub (varys) or the Kubernetes cluster. A cluster failure or varys maintenance does not affect DNS.
- **Low power** — the RPi draws ~3W idle. It can run 24/7 without meaningful electricity cost.
- **No competition for resources** — varys runs Ansible, kubectl, GitHub Actions runners, and other tools. Keeping DNS off varys means a heavy Ansible run or backup job cannot cause DNS latency.
- **Redundancy foundation** — a second Pi-hole can be added easily (e.g. on varys) as DNS Server 2 in UniFi. hodor is the primary.

---

## What Pi-hole Does Here

| Function | Detail |
|----------|--------|
| **Ad/tracker blocking** | Balanced blocklist tier — oisd (big), hagezi Pro, hagezi Threat Intelligence |
| **Split DNS (external)** | `*.kagiso.me → 10.0.10.110` (traefik-external, public apps) |
| **Split DNS (internal)** | `*.local.kagiso.me → 10.0.10.111` (traefik-internal, LAN-only apps) |
| **Recursive resolution** | All upstream queries handled by Unbound (see [02_unbound.md](02_unbound.md)) |
| **DNSSEC** | Validated by Unbound at the recursive resolver layer |

---

## Installation

### 1. Flash Raspberry Pi OS

Use Raspberry Pi Imager to flash **Raspberry Pi OS Lite (64-bit, Debian Bookworm)** to a microSD card.

In the imager's advanced options:
- Hostname: `hodor`
- Enable SSH (use key-based auth — paste your public key)
- Set locale to `Africa/Johannesburg`

### 2. Assign a Static IP in UniFi

Before booting, reserve the IP in UniFi:

```
Settings → Networks → [LAN] → DHCP → Client Reservations
  MAC address: <hodor MAC>
  IP: 10.0.10.15
```

### 3. Install Unbound First

Pi-hole's upstream will point to Unbound. Install and configure Unbound **before** Pi-hole so the upstream is ready when Pi-hole starts.

See [02_unbound.md](02_unbound.md) for the full Unbound setup.

### 4. Install Pi-hole

```bash
curl -sSL https://install.pi-hole.net | bash
```

During the interactive installer:

| Prompt | Selection |
|--------|-----------|
| Interface | `eth0` |
| Upstream DNS | Custom — `127.0.0.1#5335` (Unbound) |
| Blocklist | Default (StevenBlack) — additional lists added below |
| Admin web interface | Yes |
| Log queries | Yes |
| Privacy mode | 0 — Show Everything |

Set the admin password after install:

```bash
pihole setpassword
```

### 5. Configure Split DNS

Pi-hole uses dnsmasq under the hood. Add a custom dnsmasq config file:

```bash
sudo nano /etc/dnsmasq.d/02-kagiso-local.conf
```

```conf
# Wildcard DNS — *.kagiso.me resolves to external Traefik (public apps)
# More-specific local.kagiso.me rule below takes precedence for internal routes.
address=/.kagiso.me/10.0.10.110

# Wildcard DNS — *.local.kagiso.me resolves to internal Traefik (LAN-only apps)
# Covers: vault, cloud, grafana, prometheus, traefik, n8n, photos, auth, etc.
address=/.local.kagiso.me/10.0.10.111
```

Enable dnsmasq.d includes in Pi-hole v6:

```bash
pihole-FTL --config misc.etc_dnsmasq_d true
sudo systemctl restart pihole-FTL
```

Verify:

```bash
dig +short grafana.kagiso.me @127.0.0.1
# Expected: 10.0.10.110

dig +short vault.local.kagiso.me @127.0.0.1
# Expected: 10.0.10.111

dig +short cloudflare.com @127.0.0.1
# Expected: Cloudflare's IP (via Unbound recursive resolution)
```

### 6. Configure Upstream DNS in Pi-hole

In the Pi-hole admin UI:

```
Settings → DNS → Upstream DNS Servers
  Custom 1: 127.0.0.1#5335
  Custom 2: (leave blank — Unbound is the only upstream)
```

Uncheck all other upstream DNS providers (Cloudflare, Google, etc.). Unbound handles all recursive resolution.

---

## Blocklists

Add these in **Pi-hole Admin → Adlists**:

| List | URL | Reason |
|------|-----|--------|
| oisd big | `https://big.oisd.nl` | Broad ads/trackers/malware, very well maintained, low false positives |
| hagezi Pro | `https://raw.githubusercontent.com/hagezi/dns-blocklists/main/adblock/pro.txt` | Comprehensive ads, trackers, telemetry |
| hagezi Threat Intelligence | `https://raw.githubusercontent.com/hagezi/dns-blocklists/main/adblock/tif.txt` | Malware, phishing, ransomware C2 domains |
| Steven Black (default) | Already included by Pi-hole installer | Baseline unified hosts list |

After adding lists, update Gravity:

```bash
pihole -g
```

---

## UniFi DHCP Configuration

Point all LAN devices at hodor for DNS:

```
Settings → Networks → [LAN] → DHCP
  DNS Server 1: 10.0.10.15   (hodor — primary Pi-hole)
  DNS Server 2: 1.1.1.1      (Cloudflare — fallback if hodor is down)
```

When a second Pi-hole is deployed (e.g. on varys), replace `1.1.1.1` with its IP.

---

## Maintenance

```bash
# Update gravity (blocklists)
pihole -g

# Check status
pihole status

# Tail query log
pihole tail

# Temporarily disable blocking (60 seconds)
pihole disable 60

# Re-enable blocking
pihole enable

# Update Pi-hole
pihole update
```

Admin UI: `http://10.0.10.15/admin`

---

## Adding a New Internal Service

When a new app is deployed on `*.local.kagiso.me`, **no DNS changes are needed**. The wildcard `address=/.local.kagiso.me/10.0.10.111` covers all subdomains automatically.

When a new app is deployed on `*.kagiso.me` for internal-only access, also no changes needed — the `address=/.kagiso.me/10.0.10.110` wildcard covers it.

---

## Related

- [02_unbound.md](02_unbound.md) — Recursive DNS resolver (upstream for Pi-hole)
- [Architecture: Networking](../../docs/architecture/networking.md)
- [ADR-014: Pi-hole + Unbound DNS Architecture](../../docs/adr/ADR-014-pihole-unbound-dns.md)
