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
├── docker-vm (2 vCPU, 6GB RAM, 80GB)
│   └── Docker
│       └── Media services (Sonarr, Radarr, Plex, Prowlarr)
└── staging-k3s (2 vCPU, 8GB RAM, 60GB)
    └── k3s (single node)
        └── Flux → clusters/staging → apps/staging

k3s prod cluster (monitoring now covers external targets)
└── kube-prometheus-stack
    ├── scrapes: TrueNAS (10.0.10.80)
    ├── scrapes: docker-vm (10.0.10.21)
    └── scrapes: RPi (10.0.10.10)
```

The Docker monitoring stack is **decommissioned** — not carried across into `docker-vm`.
All monitoring consolidates to the k3s kube-prometheus-stack, which scrapes external
targets via `additionalScrapeConfigs`. Frees ~2GB RAM on `docker-vm`.

NFS mounts from TrueNAS are identical — `docker-vm` mounts `tera/media` the same way
the bare NUC does today. No data migration required.

A spare ThinkCentre M93p is retained as a cold spare / future 4th k3s worker.

> **Note — interim resource allocation:** Migration is proceeding with 16GB RAM.
> Proxmox (~2GB) + docker-vm (6GB) + staging-k3s (8GB) = 16GB exactly. Tight but
> functional. RAM upgrade to 32GB expected ~2026-03-23, at which point docker-vm → 8GB
> and staging-k3s → 16GB.

---

## Migration Steps

**Pre-migration (before touching the NUC):**
- [ ] Extend kube-prometheus-stack with `additionalScrapeConfigs` for TrueNAS, NUC, RPi
- [ ] Add PrometheusRule resources for infrastructure + TrueNAS alert rules in k3s
- [ ] Verify all external targets healthy in k3s Prometheus before proceeding
- [ ] Back up Docker compose files and volumes to `archive/docker-backups` on TrueNAS

**Proxmox setup:**
- [ ] Install Proxmox VE on NUC (wipe existing Ubuntu)
- [ ] Create `docker-vm` (2 vCPU, 6GB RAM, 80GB disk)
- [ ] Install Docker on docker-vm, restore media stack (Sonarr, Radarr, Plex, Prowlarr)
- [ ] Assign docker-vm IP: `10.0.10.21`
- [ ] Verify NFS mounts to TrueNAS (`tera/media`, `tera/downloads`, `archive/docker-backups`)
- [ ] Update kube-prometheus-stack scrape config: `10.0.10.20` → `10.0.10.21`
- [ ] Add Proxmox host node exporter scrape target: `10.0.10.20`

**Staging cluster:**
- [ ] Create `staging-k3s` VM (2 vCPU, 8GB RAM, 60GB disk)
- [ ] Install single-node k3s on staging-k3s VM
- [ ] Bootstrap Flux on staging (`--branch=main --path=clusters/staging`)
- [ ] Add `STAGING_KUBECONFIG` GitHub secret
- [ ] Uncomment staging health checks in `promote-to-prod.yml`

**Post-migration:**
- [ ] Order and install 32GB DDR4 SO-DIMM (2× 16GB) — ~2026-03-23
- [ ] After RAM upgrade: expand docker-vm → 8GB, staging-k3s → 16GB
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
