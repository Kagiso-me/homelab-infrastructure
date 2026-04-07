# PiKVM — KVM-over-IP

> **Status:** Planning
> **Host:** hodor Zero 2W (dedicated)
> **Stack:** PiKVM · USB HDMI capture · USB OTG

---

## What Is PiKVM

Out-of-band remote access for any machine in the homelab — keyboard, video, and mouse over the network. Useful when a node is locked out (failed SSH, bad k3s config, kernel panic, BIOS access needed).

This is a hardware alternative to JetKVM. A Pi Zero 2W with a cheap USB HDMI capture card replicates the same functionality for ~$30.

---

## Why PiKVM

| Without PiKVM | With PiKVM |
|---|---|
| Physical keyboard + monitor to recover a locked node | Browser-based KVM from anywhere on the LAN |
| Can't access BIOS remotely | Full BIOS/UEFI access over the network |
| Node rebuild requires physical presence | Remote OS reinstall via virtual media (ISO mount) |
| Recovery blocked if SSH is down | Recovery works regardless of OS state |

---

## Hardware

| Part | Notes |
|---|---|
| hodor Zero 2W | USB OTG native — no extra USB hub needed |
| USB-A to USB-C OTG cable | Connects Pi to target machine's USB port |
| HDMI to USB capture card | ~$15, any UVC-compatible device works |
| HDMI cable | Pi to target machine |
| MicroSD card (16GB+) | PiKVM OS |
| USB-C power supply | For the Pi itself |

**Total cost:** ~$25–35 (excluding parts already on hand)

---

## Architecture

```
Browser (any LAN device)
        │  HTTPS / H.264 stream
        ▼
┌─────────────────────────────────────┐
│  PiKVM  —  Pi Zero 2W               │
│                                     │
│  Web UI    ──  pikvm.kagiso.me      │
│  Video in  ──  USB HDMI capture     │
│  HID out   ──  USB OTG (keyboard +  │
│                mouse emulation)     │
└─────────────────────────────────────┘
        │ HDMI ──────────────► Target machine (video)
        │ USB OTG ───────────► Target machine (HID)
```

---

## Deployment Plan

### Step 1 — Flash PiKVM OS

Download the Pi Zero 2W image from [pikvm.org](https://pikvm.org/download/) and flash to SD card.

### Step 2 — First boot config

```bash
# On first boot, set passwords
passwd                          # root password
kvmd-htpasswd set admin         # web UI password

# Update PiKVM
pikvm-update
```

### Step 3 — Static IP

Assign a static DHCP lease on the router: `10.0.10.X` (allocate from homelab range).

### Step 4 — Internal DNS

Add a Pi-hole DNS record once Pi-hole is live:

```
pikvm.kagiso.me → 10.0.10.X
```

### Step 5 — Reverse proxy (optional)

Expose via NPM at `pikvm.kagiso.me` — LAN-only, no Cloudflare proxy. TLS via `*.kagiso.me` wildcard cert.

### Step 6 — ATX power control (optional, later)

GPIO → optocoupler circuit wired to target machine's power/reset header. Enables remote power on/off/reset from the PiKVM web UI.

---

## Security

- Web UI password-protected (set on first boot)
- LAN-only access — not exposed via Cloudflare Tunnel
- SSH access locked down to key-only
- Consider Tailscale on the Pi for remote-from-outside access in future

---

## Checklist

- [ ] Source Pi Zero 2W + HDMI capture card
- [ ] Flash PiKVM OS and complete first boot
- [ ] Assign static IP, add DNS record in Pi-hole
- [ ] Connect to first target machine (likely tywin or jaime)
- [ ] Validate video stream + keyboard/mouse in browser
- [ ] Add to NPM reverse proxy at `pikvm.kagiso.me`
- [ ] Document which machine it's connected to in `hodor/README.md`

---

## Related

- [hodor setup](../../hodor/README.md)
- [Networking architecture](../../docs/architecture/networking.md)
- [ROADMAP.md](../../ROADMAP.md)
