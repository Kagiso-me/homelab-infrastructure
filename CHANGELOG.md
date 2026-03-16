# Changelog

All infrastructure changes are recorded here. One line per event — newest first.
Full details for each entry live in [`docs/ops-log/`](docs/ops-log/).

---

## How to Add an Entry

```
- **[TYPE]** Short description of what changed → [details](docs/ops-log/YYYY-MM-DD-slug.md)
```

Types: `DEPLOY` `UPGRADE` `CONFIG` `NETWORK` `STORAGE` `SCALE` `INCIDENT` `MAINTENANCE` `SECURITY` `HARDWARE`

---

## 2026-03
- **[CONFIG]** remove Let's Encrypt, add Cloudflare Tunnel + Tailscale docs `8fe5366`
- **[CONFIG]** consolidate to Cloudflare Tunnel, remove letsencrypt-staging `bcc39cb`
- **[DEPLOY]** consolidate monitoring to k3s, decommission Docker monitoring stack `6599c0b`
- **[DEPLOY]** add ops-log, staging environment, and GitOps promotion pipeline `c2cb80c`

- **[HARDWARE]** Decision: pivot Intel NUC from bare Docker host to Proxmox VE hypervisor (docker-vm + staging-k3s VM) — pending RAM upgrade → [details](docs/ops-log/2026-03-16-pivot-nuc-to-proxmox.md)

- **[DEPLOY]** Networking platform stack: MetalLB (10.0.10.110–125) + cert-manager + Traefik v3 pinned to 10.0.10.110 → [details](docs/ops-log/2026-03-16-deploy-platform-stack.md)
- **[DEPLOY]** Initial infrastructure: 3-node k3s cluster, FluxCD v2 GitOps, SOPS/age secrets, Prometheus + Grafana + Loki monitoring stack → [details](docs/ops-log/2026-03-16-initial-infrastructure-setup.md)
