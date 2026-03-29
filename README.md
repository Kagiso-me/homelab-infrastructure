<div align="center">

<img src="https://github.com/user-attachments/assets/cba21e9d-1275-4c92-ab9b-365f31f35add" align="center" width="160px" height="160px"/>

# kagiso.me &nbsp;Â·&nbsp; homelab-infrastructure

_Infrastructure-as-code for a fully self-hosted homelab â€” GitOps-reconciled by FluxCD, secrets encrypted with SOPS + age, and observable end-to-end._

</div>

---

<div align="center">

<!-- Stack badges -->
[![k3s](https://img.shields.io/badge/k3s-v1.31-326CE5?style=for-the-badge&logo=kubernetes&logoColor=white)](https://k3s.io)&nbsp;
[![FluxCD](https://img.shields.io/badge/GitOps-FluxCD_v2-5468FF?style=for-the-badge&logo=flux&logoColor=white)](https://fluxcd.io)&nbsp;
[![SOPS](https://img.shields.io/badge/Secrets-SOPS_+_age-7C3AED?style=for-the-badge&logoColor=white)](docs/guides/03-Secrets-Management.md)&nbsp;
[![TrueNAS](https://img.shields.io/badge/Storage-TrueNAS_SCALE-F47B20?style=for-the-badge&logoColor=white)](truenas/README.md)&nbsp;
[![Prometheus](https://img.shields.io/badge/Monitoring-Prometheus_+_Grafana-E6522C?style=for-the-badge&logo=prometheus&logoColor=white)](docs/guides/09-Monitoring-Observability.md)

</div>

<div align="center">

[![Validate & Health Check](https://github.com/Kagiso-me/homelab-infrastructure/actions/workflows/validate.yml/badge.svg)](https://github.com/Kagiso-me/homelab-infrastructure/actions/workflows/validate.yml)

</div>

<div align="center">

[![Home Network](https://img.shields.io/badge/Network-10.0.10.0%2F24-22c55e?style=flat-square&logo=ubiquiti&logoColor=white)](#infrastructure)&nbsp;
[![Nodes](https://img.shields.io/badge/Nodes-3-326CE5?style=flat-square&logo=kubernetes&logoColor=white)](#kubernetes-platform)&nbsp;
[![Backups](https://img.shields.io/badge/Backups-4_layer-22c55e?style=flat-square)](#backup-strategy)&nbsp;
[![Alerts](https://img.shields.io/badge/Alertmanager-Discord-5865F2?style=flat-square&logo=discord&logoColor=white)](docs/guides/09-Monitoring-Observability.md)

</div>

---

<div align="center">

![Homelab Banner](assets/banner.svg)

</div>

---

## Why Self-Host?

Because the cloud is great â€” until it isn't.

- **Full control** over data, routing, and uptime
- **No surprise billing** â€” fixed hardware cost, zero per-GB egress
- **Treat home like a mini-enterprise** â€” proper GitOps, monitoring, alerting, DR procedures
- **Sharpen real skills** â€” Kubernetes, Ansible, observability, secrets management, ZFS
- **Everything in Git** â€” every service, every config, every secret (encrypted), fully reproducible

---

## Infrastructure

```
                            Internet
                                â”‚
                         kagiso.me (DNS)
                                â”‚
                        â”Œâ”€â”€â”€â”€â”€â”€â”€â–¼â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”
                        â”‚  Home Network     â”‚
                        â”‚  10.0.10.0/24     â”‚
                        â””â”€â”€â”€â”€â”€â”€â”€â”€â”¬â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜
                                 â”‚
              â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”¼â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”
              â”‚                  â”‚                  â”‚
   â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â–¼â”€â”€â”€â”€â”€â”€â”  â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â–¼â”€â”€â”€â”€â”€â”€â”€â”€â”  â”Œâ”€â”€â”€â”€â”€â–¼â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”
   â”‚  k3s Prod        â”‚  â”‚  Docker (bare)  â”‚  â”‚  TrueNAS        â”‚
   â”‚  3 nodes         â”‚  â”‚  Intel NUC      â”‚  â”‚  HP MicroServer â”‚
   â”‚  10.0.10.11â€“13   â”‚  â”‚  10.0.10.20     â”‚  â”‚  10.0.10.80     â”‚
   â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜  â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜  â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜
              â–²
              â”‚ kubectl / flux / ansible
   â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”´â”€â”€â”€â”€â”€â”€â”
   â”‚   varys NUC     â”‚
   â”‚  Control hub    â”‚
   â”‚  10.0.10.10     â”‚
   â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜
              â–²
              â”‚ SSH
         Your Laptop
```

| Component | Host | IP | Description |
|-----------|------|----|-------------|
| **k3s API VIP** | kube-vip | `10.0.10.100` | Stable Kubernetes API endpoint for kubeconfig, Flux, and automation |
| **k3s server** | tywin | `10.0.10.11` | Control-plane + workload node; embedded etcd member |
| **k3s server** | tyrion | `10.0.10.12` | Control-plane + workload node; embedded etcd member |
| **k3s server** | jaime | `10.0.10.13` | Control-plane + workload node; embedded etcd member |
| **Docker host** | docked | `10.0.10.20` | Intel NUC i3-7100U â€” bare metal Docker, media stack |
| **Control hub** | varys | `10.0.10.10` | Intel NUC i3-5010U â€” kubectl, flux, ansible, GitHub runner, Pi-hole, Grafana, Alertmanager |
| **Secondary node** | bran | `n/a` | RPi 3B+ â€” secondary Pi-hole, Tailscale exit node, WOL proxy (legacy / non-primary) |
| **TrueNAS** | truenas | `10.0.10.80` | HP MicroServer Gen8 â€” NFS, MinIO S3, Backblaze B2 sync |

---

## Kubernetes Platform

All cluster state is declared as YAML and continuously reconciled by FluxCD v2. A merged PR is the only way anything changes.

```
git push branch â†’ open PR â†’ CI validates + cluster diff â†’ merge â†’ Flux reconciles â†’ health check
```

| Layer | Technology | Detail |
|-------|-----------|--------|
| Orchestration | k3s | Lightweight Kubernetes, embedded etcd |
| GitOps | FluxCD v2 | Kustomization + HelmRelease controllers |
| Ingress | Traefik v3 | HTTP/HTTPS routing â€” `10.0.10.110` |
| Load Balancer | MetalLB | Bare-metal ARP mode â€” pool `10.0.10.110â€“10.0.10.115` |
| TLS | cert-manager + Let's Encrypt | Wildcard `*.kagiso.me` via DNS-01 Cloudflare |
| Identity | Authentik | SSO for all cluster applications |
| Security | CrowdSec | Community threat intelligence + Traefik bouncer |
| Metrics | kube-prometheus-stack | Prometheus (in-cluster) + Grafana + Alertmanager (on varys) |
| Logs | Loki + Promtail | Log aggregation + alerting on log patterns |
| Backups | Velero + MinIO | PVC snapshot and restore via S3 API |
| Secrets | SOPS + age | Encrypted secrets committed to Git |
| Storage | NFS subdir provisioner | Dynamic PV provisioning via TrueNAS NFS |
| Databases | PostgreSQL + Redis | Shared central instances, currently single-instance on local-path storage |
| Upgrades | system-upgrade-controller | Automated k3s node upgrades via Plans |

---

## Getting Started

The homelab has four independent components. Build them in this order â€” each layer depends on the one before it.

### 1. TrueNAS â€” Storage foundation

TrueNAS provides NFS shares and the MinIO S3 endpoint that all other components depend on.

> Full guide: [truenas/README.md](truenas/README.md)

| Step | Guide |
|------|-------|
| Dataset layout and ZFS pool setup | [Dataset Layout](truenas/docs/dataset-layout.md) |
| NFS share configuration | [NFS Configuration](truenas/docs/nfs-configuration.md) |
| MinIO S3 API (Velero backend) | [MinIO Configuration](truenas/docs/minio-configuration.md) |
| Backblaze B2 offsite sync | [Backblaze Sync](truenas/docs/backblaze-sync.md) |

---

### 2. varys â€” Control hub

`varys` is the single machine from which cluster management, secret handling, and automation runs. Set this up before touching k3s.

> Full guide: [Guide 01](docs/guides/01-Node-Preparation-Hardening.md)

```bash
# From your laptop or existing admin workstation
# prepare varys as the automation host first
ansible-playbook -i ansible/inventory/homelab.yml \
  ansible/playbooks/security/ssh-hardening.yml --limit varys
```

---

### 3. k3s Cluster â€” Kubernetes

Install k3s across all three nodes with a single Ansible playbook, then bootstrap FluxCD to hand control to Git.

> Full guides: [Guide 01](docs/guides/01-Node-Preparation-Hardening.md) â†’ [Guide 02](docs/guides/02-Kubernetes-Installation.md) â†’ [Guide 04](docs/guides/04-Flux-GitOps.md)

```bash
# From varys

# 1. Prepare all nodes (SSH hardening, firewall, swap)
ansible-playbook -i ansible/inventory/homelab.yml \
  ansible/playbooks/security/ssh-hardening.yml \
  ansible/playbooks/security/firewall.yml \
  ansible/playbooks/security/disable-swap.yml

# 2. Install k3s
ansible-playbook -i ansible/inventory/homelab.yml \
  ansible/playbooks/lifecycle/install-cluster.yml

# 3. Bootstrap Flux â€” watches main branch directly
flux bootstrap github \
  --owner=Kagiso-me \
  --repository=homelab-infrastructure \
  --branch=main \
  --path=clusters/prod \
  --personal
```

---

### 4. Docker Media Server â€” Self-hosted streaming

The Docker host runs the full media acquisition and streaming stack on bare metal.

> Full guide: [docker/README.md](docker/README.md)

```bash
# SSH to the Docker host
ssh kagiso@10.0.10.20

# Deploy stacks in order
cd /srv/docker
docker compose -f compose/media-stack.yml up -d
docker compose -f compose/monitoring-stack.yml up -d
docker compose -f compose/proxy-stack.yml up -d
```

---

## Backup Strategy

Four independent backup layers ensure no single failure causes data loss.

```
Layer 1 â€” Git          Kubernetes manifests + configs    Always current (every commit)
Layer 2 â€” etcd         k3s snapshots â†’ MinIO             Every 6 hours (7 retained)
Layer 3 â€” Velero       PVC data via MinIO S3             Daily 03:00 â†’ TrueNAS (7d)
Layer 4 â€” Offsite      TrueNAS â†’ Backblaze B2            Nightly cloud sync (30d)
```

Control-hub key material (age key, SSH keys, kubeconfig) is separately backed up encrypted to TrueNAS with GPG AES-256.

> Full strategy: [Guide 10 â€” Backups & Disaster Recovery](docs/guides/10-Backups-Disaster-Recovery.md)

---

## Projects

Custom applications, operational tooling, and platform initiatives built on top of this infrastructure.

â†’ **[View project board](projects/README.md)**

| Project | Type | Description |
|---------|------|-------------|
| [Beesly](projects/DEV-beesly/) | `DEV` | Personal AI assistant â€” voice, alerts, calendar, reminders |
| [Pulse](projects/DEV-pulse/) | `DEV` | Self-hosted uptime & incident monitoring platform |
| [kagiso.me](projects/OPS-kagiso-me.github.io/) | `OPS` | Personal website and portfolio |

---

## Deployment Guides

A 13-guide series that walks through building and operating the full platform from bare metal. Guides follow the exact Flux deployment order â€” what gets deployed first is documented first.

![Deployment guide journey](assets/guide-journey.svg)

| Phase | Guide | Topic |
|-------|-------|-------|
| **Foundations** | [00 â€” Platform Philosophy](docs/guides/00-Platform-Philosophy.md) | Design principles and architectural decisions |
| | [00.5 â€” Infrastructure Prerequisites](docs/guides/00.5-Infrastructure-Prerequisites.md) | TrueNAS datasets, NFS exports, MinIO, Cloudflare API token |
| **Cluster Build** | [01 â€” Node Preparation & Hardening](docs/guides/01-Node-Preparation-Hardening.md) | OS prep, SSH hardening, firewall, nfs-common |
| | [02 â€” Kubernetes Installation](docs/guides/02-Kubernetes-Installation.md) | k3s install via Ansible across 3 nodes |
| **GitOps Bootstrap** | [03 â€” Secrets Management](docs/guides/03-Secrets-Management.md) | SOPS + age â€” encrypt secrets for Git |
| | [04 â€” Flux GitOps Bootstrap](docs/guides/04-Flux-GitOps.md) | FluxCD v2, PR validation pipeline, self-hosted runner |
| **Platform Services** | [05 â€” Networking: MetalLB & Traefik](docs/guides/05-Networking-MetalLB-Traefik.md) | Layer-2 load balancing and ingress routing |
| | [06 â€” Security: cert-manager & TLS](docs/guides/06-Security-CertManager-TLS.md) | Automated wildcard certificates via Let's Encrypt |
| | [07 â€” Namespaces & Cluster Identity](docs/guides/07-Namespaces-Cluster-Identity.md) | Namespace layout, node labels, scheduling rules |
| | [08 â€” Storage Architecture](docs/guides/08-Storage-Architecture.md) | NFS provisioner, PVC lifecycle, TrueNAS datasets |
| | [09 â€” Monitoring & Observability](docs/guides/09-Monitoring-Observability.md) | Prometheus + Grafana + Loki + external targets |
| | [10 â€” Backups & Disaster Recovery](docs/guides/10-Backups-Disaster-Recovery.md) | etcd snapshots + Velero + MinIO |
| | [11 â€” Platform Upgrade Controller](docs/guides/11-Platform-Upgrade-Controller.md) | Automated k3s upgrades via system-upgrade-controller |
| **Applications & Ops** | [12 â€” Applications via GitOps](docs/guides/12-Applications-GitOps.md) | Deploying apps with Flux HelmReleases |
| | [13 â€” Platform Operations & Lifecycle](docs/guides/13-Platform-Operations-Lifecycle.md) | Node maintenance, incident response, disaster recovery |

---

## Repository Structure

```
homelab-infrastructure/
â”‚
â”œâ”€â”€ clusters/
â”‚   â””â”€â”€ prod/            # Flux entry points â€” watches main branch
â”œâ”€â”€ platform/            # Cluster-wide platform components (HelmReleases)
â”‚   â”œâ”€â”€ networking/      # MetalLB, Traefik
â”‚   â”œâ”€â”€ security/        # cert-manager, Authentik, CrowdSec, ClusterIssuers
â”‚   â”œâ”€â”€ observability/   # kube-prometheus-stack, Loki, Alertmanager, daily-digest
â”‚   â”œâ”€â”€ storage/         # NFS provisioner, StorageClasses
â”‚   â”œâ”€â”€ backup/          # Velero + MinIO credentials
â”‚   â”œâ”€â”€ databases/       # PostgreSQL + Redis (shared, control-plane pinned)
â”‚   â”œâ”€â”€ upgrade/         # system-upgrade-controller + Plans
â”‚   â””â”€â”€ namespaces/      # Namespace declarations
â”œâ”€â”€ apps/                # Application workloads
â”‚   â”œâ”€â”€ base/            # Per-app manifests (HelmRelease, IngressRoute, Secret)
â”‚   â””â”€â”€ prod/            # Production kustomization â€” lists active apps
â”œâ”€â”€ ansible/             # Ansible â€” node provisioning and maintenance
â”‚   â”œâ”€â”€ inventory/       # homelab.yml â€” all nodes
â”‚   â”œâ”€â”€ playbooks/
â”‚   â”‚   â”œâ”€â”€ lifecycle/   # install-cluster.yml, install-platform.yml, purge-k3s.yml
â”‚   â”‚   â”œâ”€â”€ security/    # ssh-hardening, firewall, fail2ban, time-sync
â”‚   â”‚   â””â”€â”€ maintenance/ # upgrade-nodes.yml, reboot-nodes.yml
â”‚   â””â”€â”€ roles/k3s_install/
â”‚
â”œâ”€â”€ raspberry-pi/        # Raspberry Pi secondary-node docs and services
â”œâ”€â”€ docker/              # Docker media server (10.0.10.20)
â”œâ”€â”€ truenas/             # TrueNAS HP MicroServer Gen8 (10.0.10.80)
â”‚
â””â”€â”€ docs/                # Cross-cutting documentation
    â”œâ”€â”€ guides/          # 13-guide deployment series (00â€“13)
    â”œâ”€â”€ adr/             # Architecture Decision Records
    â”œâ”€â”€ architecture/    # Platform overview diagrams
    â”œâ”€â”€ compliance/      # Backup policy, DR plan, security policy
    â””â”€â”€ operations/
        â””â”€â”€ runbooks/    # Cluster rebuild, node replacement, alert responses
```

---

## CI/CD

| Workflow | Trigger | Purpose |
|---------|---------|---------|
| [validate.yml](.github/workflows/validate.yml) | PR (infra paths) | kubeconform + kustomize build + pluto validation |
| [validate.yml](.github/workflows/validate.yml) | PR (infra paths) | `flux diff` posted as collapsible PR comment (self-hosted runner) |
| [validate.yml](.github/workflows/validate.yml) | Push to `main` | Flux reconcile + kustomization health + Traefik smoke test |

All cluster-touching jobs run on a **self-hosted runner on `varys` (10.0.10.10)**, giving the pipeline direct LAN access to the prod cluster. See [ADR-007](docs/adr/ADR-007-self-hosted-runners.md).

---

## Architecture Documentation

| Document | Description |
|----------|-------------|
| [Platform Overview](docs/architecture/platform-overview.md) | Component map and interaction model |
| [Cluster Architecture](docs/architecture/cluster-architecture.md) | Node layout, networking, storage |
| [Networking](docs/architecture/networking.md) | MetalLB, Traefik, DNS, TLS |
| [Monitoring](docs/architecture/monitoring.md) | Observability stack design |
| [ADR Index](docs/adr/) | Architecture Decision Records |

---

## Operations

| Document | Description |
|----------|-------------|
| [Cluster Rebuild](docs/operations/runbooks/cluster-rebuild.md) | Full recovery procedure â€” RTO 90â€“120 min |
| [Node Replacement](docs/operations/runbooks/node-replacement.md) | Replace a failed cluster node |
| [Backup Restoration](docs/operations/runbooks/backup-restoration.md) | Velero restore procedures |
| [Certificate Failure](docs/operations/runbooks/certificate-failure.md) | TLS cert troubleshooting |
| [Alert Runbooks](docs/operations/runbooks/alerts/) | Per-alert response procedures |

---

## License

MIT

