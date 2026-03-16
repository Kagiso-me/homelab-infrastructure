# 2026-03-16 — HARDWARE: Pivot Intel NUC to Proxmox

**Operator:** Kagiso
**Type:** `HARDWARE`
**Components:** Intel NUC NUC7i3BNH · Proxmox VE · Docker VM · Staging k3s
**Status:** 🔄 In Progress — executing 2026-03-16
**Downtime:** Full Docker host downtime during migration (~2–4 hours)

---

## What Changed

The Intel NUC is being converted from a bare Docker host to a Proxmox VE hypervisor.
Two VMs will replace the bare OS: one for Docker workloads, one for the staging k3s cluster.

This is a deliberate architectural pivot — not a fix for something broken, but a step up
in infrastructure maturity. The bare Docker model served its purpose during the initial
build. This change unlocks the staging environment needed for the GitOps promotion pipeline
and gives each workload clean isolation.

---

## Why

Two things pushed this decision:

**1. Staging environment needed.**
The GitOps promotion pipeline (main → staging → prod) is built and waiting. Without a
staging cluster, every change goes directly to production. The NUC has the headroom to
run a single-node k3s staging cluster — Proxmox is the cleanest way to host it alongside
the existing Docker workloads.

**2. Workload isolation.**
Running k3s and Docker side-by-side on a bare OS is messy — shared kernel, port conflicts,
network complexity. VMs solve this properly.

---

## Before (current state)

```
NUC (bare Ubuntu)
└── Docker
    ├── Prometheus
    ├── Grafana
    ├── Loki
    ├── Alertmanager
    └── Media services (Sonarr, Radarr, Plex)
```

## After (target state)

```
NUC (Proxmox VE)
├── docker-vm (2 vCPU, 8GB RAM, 80GB)
│   └── Docker
│       ├── Prometheus
│       ├── Grafana
│       ├── Loki
│       ├── Alertmanager
│       └── Media services
└── staging-k3s (2 vCPU, 6GB RAM, 60GB)
    └── k3s (single node)
        └── Flux → clusters/staging → apps/staging
```

NFS mounts from TrueNAS are identical — `docker-vm` mounts `tera/media` the same way
the bare NUC does today. No data migration required.

> **Note — interim resource allocation:** Migration is proceeding with 16GB RAM
> before the planned 32GB upgrade. Proxmox (~2GB) + docker-vm (8GB) + staging-k3s (6GB)
> = 16GB exactly. Tight but functional. RAM upgrade expected ~2026-03-23, at which point
> docker-vm will be expanded to 12GB and staging-k3s to 10GB.

---

## Migration Steps

- [ ] Back up Docker compose files and volumes to `archive/docker-backups` on TrueNAS
- [ ] Install Proxmox VE on NUC (wipe existing Ubuntu)
- [ ] Create `docker-vm` (2 vCPU, 8GB, 80GB), install Docker, restore stack
- [ ] Verify NFS mounts to TrueNAS (`tera/media`, `tera/downloads`, `archive/docker-backups`)
- [ ] Verify monitoring stack healthy (Prometheus, Grafana, Loki, Alertmanager)
- [ ] Create `staging-k3s` VM (2 vCPU, 6GB, 60GB), install k3s single-node
- [ ] Bootstrap Flux on staging (`--branch=main --path=clusters/staging`)
- [ ] Add `STAGING_KUBECONFIG` GitHub secret
- [ ] Uncomment staging health checks in `promote-to-prod.yml`
- [ ] Order and install 32GB DDR4 SO-DIMM (2× 16GB) — ~2026-03-23
- [ ] Expand docker-vm to 12GB, staging-k3s to 10GB after RAM upgrade
- [ ] Update this entry status to ✅ Complete

---

## Rollback

If Proxmox install goes wrong — bare metal reinstall of Ubuntu and restore Docker
stack from `archive/docker-backups`. TrueNAS media is untouched throughout.

---

## Related

- ADR: `docs/architecture/decisions/ADR-006-proxmox-pivot.md`
- Staging cluster config: `clusters/staging/`
- Promotion pipeline: `.github/workflows/promote-to-prod.yml`
- Docker backup runbook: `docs/operations/runbooks/alerts/backup-runbooks.md`
