# 2026-04 — DEPLOY: Migrate all CI runners from varys to bran

**Operator:** Kagiso
**Type:** `DEPLOY`
**Components:** GitHub Actions · self-hosted runners · varys · bran (RPi 4)
**Commit:** —
**Downtime:** None (runners registered in parallel before deregistering old)

---

## What Changed

Deregistered all GitHub Actions self-hosted runners from `varys` (Intel NUC repurposed as Proxmox host) and registered equivalent runners on `bran` (Raspberry Pi 4, 10.0.10.9). Updated all workflow files to reference the new runner labels.

---

## Why

`varys` is being transitioned to a Proxmox hypervisor to host VMs. Running GitHub Actions runners directly on the bare metal of a hypervisor host adds unnecessary risk — a runaway job could affect VM guests, and the host needs to be managed as infrastructure, not as a general-purpose compute node. `bran` was already set up as a dedicated observer node and is the right home for site-adjacent CI workloads (fetching live data, generating the digest, building the site).

---

## Details

- **Runners migrated**: `site-runner`, `bran-site`, `homelab-runner`
- **Old host**: `varys` (Intel NUC, x86_64, Ubuntu 22.04 bare metal)
- **New host**: `bran` (Raspberry Pi 4 4GB, aarch64, Ubuntu 24.04)
- Runner registration: `./config.sh --url https://github.com/Kagiso-me/kagiso-me.github.io --token <token> --labels bran-site,linux,homelab`
- Service: `svc.sh install && svc.sh start` (runs as `actions-runner` systemd service)
- Workflow labels updated: `runs-on: [self-hosted, linux, homelab, bran-site]`
- Old runners deregistered via GitHub UI after confirming new runners picked up jobs

---

## Outcome

- All workflows running successfully on `bran` ✓
- `varys` runners deregistered ✓
- Live data fetch, digest generation, and site build all confirmed working on aarch64 ✓
- `varys` free to be managed purely as Proxmox host ✓

---

## Related

- bran setup: `docs/guides/bran-setup.md`
- Site workflows: `.github/workflows/` in kagiso-me.github.io
