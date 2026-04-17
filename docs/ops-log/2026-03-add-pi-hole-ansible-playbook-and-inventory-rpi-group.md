# 2026-03 — DEPLOY: Add Pi-hole Ansible playbook and inventory rpi group

**Operator:** Kagiso
**Type:** `DEPLOY`
**Components:** Pi-hole · Ansible · bran · DNS
**Commit:** —
**Downtime:** ~2 min (DNS briefly interrupted during Pi-hole install)

---

## What Changed

Added an Ansible playbook to configure Pi-hole on Raspberry Pi hosts and added a `rpi` inventory group. `bran` is the first member of this group. Pi-hole serves as the LAN DNS resolver with ad-blocking and custom local DNS entries.

---

## Why

The homelab needed a reliable LAN DNS server for two reasons:
1. Ad-blocking at the network level — covers all devices including IoT and smart TVs that can't run extensions
2. Custom DNS for local hostnames (`*.local.kagiso.me`, node names, TrueNAS, MikroTik) without modifying every device's hosts file

Using a Raspberry Pi (bran) for DNS rather than a k3s service means DNS stays up even when the cluster is restarting or unhealthy. The cluster's CoreDNS handles in-cluster resolution; Pi-hole handles everything else on LAN.

---

## Details

- **Pi-hole install method**: official install script via Ansible `shell` task (not yet a proper Ansible role — later refactored)
- **Inventory group `rpi`**: separate from `k3s_nodes`, uses `ansible_user: ubuntu`, different SSH key
- **Custom DNS entries provisioned by playbook**:
  - Node IPs (jaime, tyrion, tywin, bran, varys)
  - TrueNAS: `10.0.10.80`
  - MikroTik: `10.0.10.1`
  - Traefik external: `10.0.10.110`
  - Traefik internal: `10.0.10.111`
- **Upstream DNS**: Cloudflare `1.1.1.1` and `1.0.0.1` (no Google DNS)
- **MikroTik DHCP**: DNS servers pointed at bran IP (`10.0.10.9`)

---

## Outcome

- Pi-hole running on bran ✓
- All LAN devices using bran as DNS resolver ✓
- Custom DNS entries resolving ✓
- Ad-blocking active (blocklist: Steven Black's combined list) ✓

---

## Related

- Pi-hole playbook: `ansible/playbooks/pihole.yml`
- Inventory: `ansible/inventory/hosts.yml`
