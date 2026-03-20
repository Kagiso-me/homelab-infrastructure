# ADR-006 — Pivot Docker Host to Proxmox Hypervisor

**Date:** 2026-03-16
**Status:** Accepted
**Author:** Kagiso Tjeane

---

## Context

The Intel NUC NUC7i3BNH (i3-7100U, 16GB DDR4, 256GB NVMe) has been running as a bare
Docker host since the initial infrastructure build. It runs the monitoring stack
(Prometheus, Grafana, Loki, Alertmanager) and media services (Sonarr, Radarr, Plex).

Two requirements emerged that the bare Docker model cannot satisfy cleanly:

1. **A staging Kubernetes environment** is needed as part of the GitOps promotion pipeline.
   The k3s cluster (3× ThinkCentre M93p) serves as production. Changes should pass through
   a staging cluster before reaching production. A single-node k3s instance on the NUC is
   the most cost-effective staging environment given current hardware.

2. **Workload isolation** — running a Kubernetes node and Docker services on the same bare OS
   introduces scheduling and networking complexity. VMs provide clean isolation with defined
   resource boundaries.

Proxmox VE is a Type-1 hypervisor that runs directly on hardware and manages VMs and
containers. It is open source, widely used in homelab environments, and has no licensing cost.

---

## Decision

Convert the Intel NUC from a bare Docker host to a **Proxmox VE hypervisor**.

Run two VMs on the Proxmox host:

| VM | vCPU | RAM | Disk | Purpose |
|----|------|-----|------|---------|
| `docker-vm` | 2 | 6GB | 80GB | Docker workloads (media services only) |
| `staging-k3s` | 2 | 8GB | 60GB | Single-node k3s staging cluster |

The Docker monitoring stack (Prometheus, Grafana, Loki, Alertmanager) is **not** carried
across into `docker-vm`. Monitoring is consolidated to the k3s kube-prometheus-stack,
which scrapes external targets (TrueNAS, docker-vm, RPi) via `additionalScrapeConfigs`.
This frees ~2GB RAM on docker-vm and eliminates a duplicate monitoring stack.

RAM will be upgraded from 16GB to 32GB (2× 16GB SO-DIMM DDR4) after initial migration.
After upgrade: docker-vm → 8GB, staging-k3s → 16GB, ~6GB buffer.

Media files remain on TrueNAS `tera` pool, mounted via NFS to `docker-vm` — identical
to the current bare-metal NFS mount. No data migration required.

A spare Lenovo ThinkCentre M93p (i5-4570T, 16GB DDR3) is retained as a cold spare
and is a candidate for a 4th k3s worker node when cluster capacity is needed.

---

## Why Not Alternatives

**Continue with bare Docker + separate staging machine**
Would require additional hardware. The NUC already has sufficient resources if RAM is
upgraded. Unnecessary cost.

**Run k3s directly on the bare NUC alongside Docker**
Technically possible but creates a messy environment — shared kernel, potential port
conflicts, complex network routing between Docker and k3s. Not worth the operational debt.

**Use a cloud VM for staging**
Adds recurring cost and external dependency. The goal is a self-contained homelab.
Proxmox on the NUC achieves staging isolation at zero recurring cost.

---

## Consequences

**Positive:**
- Clean workload isolation — Docker and k3s each get their own VM
- Staging environment unblocks the full GitOps promotion pipeline
- Proxmox provides VM snapshots — easy rollback during migrations
- Resource limits per VM prevent one workload starving the other
- Future flexibility — additional VMs can be added as needed

**Negative / trade-offs:**
- One-time migration effort required (estimated 2–4 hours)
- Proxmox host overhead (~2GB RAM, minimal CPU)
- i3-7100U is dual-core — CPU is the binding constraint, not RAM
- iGPU passthrough for Plex hardware transcoding requires additional configuration
  (not needed — all media is direct-played; see note below)

**Note on transcoding:**
All media in the library is direct-played. A scheduled conversion job will be built
to proactively re-encode any file that would require transcoding, ensuring the library
stays compatible with Plex/Jellyfin native clients. This eliminates the need for
runtime hardware transcoding entirely.

---

## Migration Plan

1. Upgrade NUC RAM: 16GB → 32GB (SO-DIMM DDR4)
2. Install Proxmox VE on NUC (bare metal install, wipes existing OS)
3. Create `docker-vm` — install Docker, restore compose stacks
4. Verify NFS mounts from TrueNAS
5. Create `staging-k3s` — install single-node k3s
6. Bootstrap Flux on staging cluster (`--branch=main --path=clusters/staging`)
7. Add `STAGING_KUBECONFIG` to GitHub secrets
8. Activate staging health checks in `promote-to-prod.yml`

---

## Related

- Previous architecture: `docker/` directory — retained as historical reference
- Staging cluster config: `clusters/staging/`
- Promotion pipeline: `.github/workflows/promote-to-prod.yml`
- Ops log: `docs/ops-log/2026-03-16-pivot-nuc-to-proxmox.md`
