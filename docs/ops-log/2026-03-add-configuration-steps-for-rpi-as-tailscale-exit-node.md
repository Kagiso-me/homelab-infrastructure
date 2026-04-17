# 2026-03 — DEPLOY: Add configuration steps for RPi as Tailscale exit node

**Operator:** Kagiso
**Type:** `DEPLOY`
**Components:** Tailscale · bran · Ansible · VPN
**Commit:** —
**Downtime:** None

---

## What Changed

Configured `bran` (Raspberry Pi 4) as a Tailscale exit node, allowing remote access to the homelab network from anywhere. Added the configuration steps to the Ansible playbook for bran.

---

## Why

When away from home, accessing internal services (`*.local.kagiso.me`, TrueNAS, MikroTik) requires a VPN tunnel back to the homelab network. Tailscale is the right tool for this: it uses WireGuard under the hood, requires no port forwarding or exposed VPN endpoints, works through CGNAT, and installs in minutes.

bran is the exit node rather than a k3s node because bran is lower stakes — a misconfigured Tailscale exit node doesn't risk cluster stability.

---

## Details

- **Tailscale install**: `tailscale` package from official apt repo, added to Ansible playbook
- **Exit node enablement**: `tailscale up --advertise-exit-node --accept-dns=false`
- **Route advertisement**: bran advertises `10.0.10.0/24` (homelab LAN) to Tailscale network
- **MagicDNS**: disabled on bran — Pi-hole handles DNS, not Tailscale's MagicDNS
- **Approval**: exit node and subnet routes approved in Tailscale admin console
- **Client setup**: Tailscale iOS/macOS app configured to use bran as exit node when away from home

---

## Outcome

- bran registered as Tailscale exit node ✓
- Full homelab network accessible via Tailscale from remote ✓
- `*.local.kagiso.me` reachable over Tailscale (Pi-hole DNS resolves correctly) ✓

---

## Related

- bran Ansible playbook: `ansible/playbooks/bran.yml`
- Tailscale ACL: managed in Tailscale admin console
