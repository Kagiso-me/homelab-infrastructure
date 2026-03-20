<div align="center">

<img src="https://github.com/user-attachments/assets/cba21e9d-1275-4c92-ab9b-365f31f35add" align="center" width="160px" height="160px"/>

# kagiso.me &nbsp;·&nbsp; homelab-infrastructure

_Infrastructure-as-code for a fully self-hosted homelab — GitOps-reconciled by FluxCD, secrets encrypted with SOPS + age, and observable end-to-end._

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

<!-- CI/CD — your own GitHub Actions workflows -->
[![Validate Manifests](https://github.com/Kagiso-me/homelab-infrastructure/actions/workflows/validate.yml/badge.svg)](https://github.com/Kagiso-me/homelab-infrastructure/actions/workflows/validate.yml)&nbsp;
[![flux-local diff](https://github.com/Kagiso-me/homelab-infrastructure/actions/workflows/flux-local.yml/badge.svg)](https://github.com/Kagiso-me/homelab-infrastructure/actions/workflows/flux-local.yml)

</div>

<div align="center">

<!-- Operational status — wire these up to your Uptime Kuma / Gatus instance at kagiso.me once live -->
<!-- Replace the endpoint URLs with your own Uptime Kuma status badge API once the stack is running -->
[![Home Network](https://img.shields.io/badge/Network-10.0.10.0%2F24-22c55e?style=flat-square&logo=ubiquiti&logoColor=white)](#infrastructure)&nbsp;
[![Nodes](https://img.shields.io/badge/Nodes-3-326CE5?style=flat-square&logo=kubernetes&logoColor=white)](#kubernetes-platform)&nbsp;
[![Backups](https://img.shields.io/badge/Backups-4_layer-22c55e?style=flat-square)](#backup-strategy)&nbsp;
[![Alerts](https://img.shields.io/badge/Alertmanager-Slack-4A154B?style=flat-square&logo=slack&logoColor=white)](docs/guides/09-Monitoring-Observability.md)

</div>

---

<div align="center">

![Homelab Banner](assets/banner.svg)

</div>

---

## Why Self-Host?

Because the cloud is great — until it isn't.

- **Full control** over data, routing, and uptime
- **No surprise billing** — fixed hardware cost, zero per-GB egress
- **Treat home like a mini-enterprise** — proper GitOps, monitoring, alerting, DR procedures
- **Sharpen real skills** — Kubernetes, Ansible, observability, secrets management, ZFS
- **Everything in Git** — every service, every config, every secret (encrypted), fully reproducible

---

## Infrastructure

```
                            Internet
                                │
                         kagiso.me (DNS)
                                │
                        ┌───────▼──────────┐
                        │  Home Network     │
                        │  10.0.10.0/24     │
                        └────────┬──────────┘
                                 │
              ┌──────────────────┼──────────────────┐
              │                  │                  │
   ┌──────────▼──────┐  ┌───────▼──────┐  ┌────────▼────────┐
   │  k3s Prod        │  │ k3s Staging  │  │  TrueNAS        │
   │  3 nodes         │  │ Proxmox VM   │  │  HP MicroServer │
   │  10.0.10.11–13   │  │  10.0.10.31  │  │  10.0.10.80     │
   └──────────────────┘  └──────────────┘  └─────────────────┘
              ▲
              │ kubectl / flux / ansible
   ┌──────────┴──────┐
   │  Raspberry Pi   │
   │  Control hub    │
   │  10.0.10.10     │
   └─────────────────┘
              ▲
              │ SSH
         Your Laptop
```

| Component | Host | IP | Description |
|-----------|------|----|-------------|
| **k3s control plane** | tywin | `10.0.10.11` | Kubernetes API server, etcd, scheduler |
| **k3s worker** | jaime | `10.0.10.12` | Application workloads |
| **k3s worker** | tyrion | `10.0.10.13` | Application workloads |
| **Proxmox host** | nuc | `10.0.10.30` | Intel NUC hypervisor (Proxmox VE) |
| **k3s staging** | staging-vm | `10.0.10.31` | Single-node staging cluster on Proxmox — watches `main` branch |
| **Docker VM** | docker-vm | `10.0.10.32` | Docker media stack VM on Proxmox |
| **Raspberry Pi** | rpi | `10.0.10.10` | Control hub — kubectl, flux, ansible, cron backups |
| **TrueNAS** | truenas | `10.0.10.80` | HP MicroServer Gen8 — NFS, MinIO S3, Backblaze B2 sync |

---

## Kubernetes Platform

All cluster state is declared as YAML and continuously reconciled by FluxCD v2. A `git push` is the only way anything changes.

```
git push → FluxCD detects change → reconciles cluster state → done
```

| Layer | Technology | Detail |
|-------|-----------|--------|
| Orchestration | k3s | Lightweight Kubernetes, embedded etcd |
| GitOps | FluxCD v2 | Kustomization + HelmRelease controllers |
| Ingress | Traefik v3 | HTTP/HTTPS routing — `10.0.10.110` |
| Load Balancer | MetalLB | Bare-metal ARP mode — pool `10.0.10.110–10.0.10.125` |
| TLS | cert-manager + Let's Encrypt | Automatic certificate lifecycle |
| Metrics | kube-prometheus-stack | Prometheus + Grafana + Alertmanager |
| Logs | Loki + Promtail | Log aggregation + alerting on log patterns |
| Backups | Velero + MinIO | PVC snapshot and restore via S3 API |
| Secrets | SOPS + age | Encrypted secrets committed to Git |
| Storage | NFS subdir provisioner | Dynamic PV provisioning via TrueNAS NFS |
| Upgrades | system-upgrade-controller | Automated k3s node upgrades via Plans |

---

## Getting Started

The homelab has four independent components. Build them in this order — each layer depends on the one before it.

### 1. TrueNAS — Storage foundation

TrueNAS provides NFS shares and the MinIO S3 endpoint that all other components depend on.

> Full guide: [truenas/README.md](truenas/README.md)

| Step | Guide |
|------|-------|
| Dataset layout and ZFS pool setup | [Dataset Layout](truenas/docs/dataset-layout.md) |
| NFS share configuration | [NFS Configuration](truenas/docs/nfs-configuration.md) |
| MinIO S3 API (Velero backend) | [MinIO Configuration](truenas/docs/minio-configuration.md) |
| Backblaze B2 offsite sync | [Backblaze Sync](truenas/docs/backblaze-sync.md) |

---

### 2. Raspberry Pi — Control hub

The RPi is the single machine from which all cluster management, secret handling, and automation runs. Set this up before touching k3s.

> Full guide: [raspberry-pi/README.md](raspberry-pi/README.md)

```bash
# From your laptop — bootstrap the RPi via Ansible
ansible-playbook -i raspberry-pi/ansible/inventory/hosts.yml \
  raspberry-pi/ansible/playbooks/setup.yml
```

| Step | Guide |
|------|-------|
| OS installation and Ansible bootstrap | [01 — Setup](raspberry-pi/docs/01_setup.md) |
| Services (Pi-hole, Uptime Kuma, Homer) | [02 — Services](raspberry-pi/docs/02_services.md) |
| Key material backup | [03 — Backup](raspberry-pi/docs/03_backup.md) |

---

### 3. k3s Cluster — Kubernetes

Install k3s across all three nodes with a single Ansible playbook, then install the networking platform (MetalLB + cert-manager + Traefik).

> Full guides: [Guide 01](docs/guides/01-Node-Preparation-Hardening.md) → [Guide 02](docs/guides/02-Kubernetes-Installation.md) → [Guide 05](docs/guides/05-Networking-MetalLB-Traefik.md)

```bash
# From the Raspberry Pi

# 1. Prepare all nodes (SSH hardening, firewall, swap)
ansible-playbook -i ansible/inventory/homelab.yml \
  ansible/playbooks/security/ssh-hardening.yml \
  ansible/playbooks/security/firewall.yml \
  ansible/playbooks/security/disable-swap.yml

# 2. Install k3s
ansible-playbook -i ansible/inventory/homelab.yml \
  ansible/playbooks/lifecycle/install-cluster.yml

# 3. Install MetalLB + cert-manager + Traefik
ansible-playbook -i ansible/inventory/homelab.yml \
  ansible/playbooks/lifecycle/install-platform.yml
```

---

### 4. Docker Media Server — Self-hosted streaming

The Docker host runs the full media acquisition and streaming stack, accessible only via the RPi.

> Full guide: [docker/README.md](docker/README.md)

```bash
# SSH to the Docker host via RPi
ssh kagiso@10.0.10.32

# Deploy stacks in order
cd /srv/docker
docker compose -f compose/media-stack.yml up -d
docker compose -f compose/monitoring-stack.yml up -d
docker compose -f compose/proxy-stack.yml up -d
```

| Step | Guide |
|------|-------|
| Host installation and hardening | [01 — Install](docker/docs/01_host_installation_and_hardening.md) |
| Storage layout and NFS mounts | [02 — Filesystem](docker/docs/02_docker_installation_and_filesystem.md) |
| Media stack and reverse proxy | [03 — Media Stack](docker/docs/03_media_stack_and_reverse_proxy.md) |
| Monitoring and logging | [04 — Monitoring](docker/docs/04_monitoring_and_logging.md) |
| Backups and disaster recovery | [05 — Backups](docker/docs/05_backups_and_disaster_recovery.md) |

---

### 5. Bootstrap FluxCD — GitOps

With the cluster running and TrueNAS providing storage, bootstrap FluxCD to hand control of the cluster to Git.

> Full guide: [Guide 04 — GitOps Control Plane](docs/guides/04-Flux-GitOps.md)

```bash
# On the Raspberry Pi

# Generate the age key pair for SOPS secret encryption
age-keygen -o age.key
# Back up age.key to your password manager — never commit it to Git

# Create the sops-age Secret in each cluster before bootstrapping
kubectl create namespace flux-system
kubectl create secret generic sops-age \
  --namespace=flux-system \
  --from-file=age.agekey=age.key

# Bootstrap staging (single-node VM — watches main branch)
flux bootstrap git \
  --url=ssh://git@github.com/Kagiso-me/homelab-infrastructure.git \
  --branch=main \
  --path=clusters/staging \
  --private-key-file=$HOME/.ssh/flux_deploy_key

# Bootstrap prod (ThinkCentre cluster — watches prod branch)
# Ensure prod branch exists first: git push origin main:prod
flux bootstrap git \
  --url=ssh://git@github.com/Kagiso-me/homelab-infrastructure.git \
  --branch=prod \
  --path=clusters/prod \
  --private-key-file=$HOME/.ssh/flux_deploy_key

# Promote staging → prod at any time:
git push origin main:prod
```

Flux reconciles all platform components and application workloads from Git automatically.
Staging validates every change before it reaches production.

---

## Backup Strategy

Four independent backup layers ensure no single failure causes data loss.

```
Layer 1 — Git          Kubernetes manifests + configs    Always current (every commit)
Layer 2 — etcd         k3s snapshots + Docker appdata    Daily 02:00 → TrueNAS NFS (7d)
Layer 3 — Velero       PVC data via MinIO S3             Daily 03:00 → TrueNAS (7d)
Layer 4 — Offsite      TrueNAS → Backblaze B2            Nightly cloud sync (30d)
```

RPi key material (age key, SSH keys, kubeconfig) is separately backed up encrypted to TrueNAS with GPG AES-256.

> Full strategy: [Guide 10 — Backups & Disaster Recovery](docs/guides/10-Backups-Disaster-Recovery.md)

---

## Projects

Custom applications, operational tooling, and platform initiatives built on top of this infrastructure.

→ **[View project board](projects/README.md)**

| Project | Type | Description |
|---------|------|-------------|
| [Beesly](projects/DEV-beesly/) | `DEV` | Personal AI assistant — voice, alerts, calendar, reminders |
| [Pulse](projects/DEV-pulse/) | `DEV` | Self-hosted uptime & incident monitoring platform |
| [kagiso.me](projects/OPS-kagiso-me.github.io/) | `OPS` | Personal website and portfolio |

---

## Deployment Guides

A 13-guide series that walks through building and operating the full platform from bare metal. Guides follow the exact Flux deployment order — what gets deployed first is documented first.

| Phase | Guide | Topic |
|-------|-------|-------|
| **Foundations** | [00 — Platform Philosophy](docs/guides/00-Platform-Philosophy.md) | Design principles and architectural decisions |
| | [00.5 — Infrastructure Prerequisites](docs/guides/00.5-Infrastructure-Prerequisites.md) | TrueNAS datasets, NFS exports, MinIO, Cloudflare API token |
| **Cluster Build** | [01 — Node Preparation & Hardening](docs/guides/01-Node-Preparation-Hardening.md) | OS prep, SSH hardening, firewall, nfs-common |
| | [02 — Kubernetes Installation](docs/guides/02-Kubernetes-Installation.md) | k3s install via Ansible across 3 nodes |
| **GitOps Bootstrap** | [03 — Secrets Management](docs/guides/03-Secrets-Management.md) | SOPS + age — encrypt secrets for Git |
| | [04 — Flux GitOps Bootstrap](docs/guides/04-Flux-GitOps.md) | FluxCD v2 bootstrap, two-environment promotion model |
| **Platform Services** | [05 — Networking: MetalLB & Traefik](docs/guides/05-Networking-MetalLB-Traefik.md) | Layer-2 load balancing and ingress routing |
| | [06 — Security: cert-manager & TLS](docs/guides/06-Security-CertManager-TLS.md) | Automated wildcard certificates via Let's Encrypt |
| | [07 — Namespaces & Cluster Identity](docs/guides/07-Namespaces-Cluster-Identity.md) | Namespace layout, node labels, scheduling rules |
| | [08 — Storage Architecture](docs/guides/08-Storage-Architecture.md) | NFS provisioner, PVC lifecycle, TrueNAS datasets |
| | [09 — Monitoring & Observability](docs/guides/09-Monitoring-Observability.md) | Prometheus + Grafana + Loki + SMART alerting |
| | [10 — Backups & Disaster Recovery](docs/guides/10-Backups-Disaster-Recovery.md) | etcd snapshots + Velero + MinIO |
| | [11 — Platform Upgrade Controller](docs/guides/11-Platform-Upgrade-Controller.md) | Automated k3s upgrades via system-upgrade-controller |
| **Applications & Ops** | [12 — Applications via GitOps](docs/guides/12-Applications-GitOps.md) | Deploying apps with Flux HelmReleases |
| | [13 — Platform Operations & Lifecycle](docs/guides/13-Platform-Operations-Lifecycle.md) | Node maintenance, incident response, disaster recovery |

---

## Repository Structure

```
homelab-infrastructure/
│
├── clusters/
│   ├── prod/            # Prod Flux entry points — watches prod branch
│   └── staging/         # Staging Flux entry points — watches main branch
├── platform/               # Cluster-wide platform components (HelmReleases)
│   ├── networking/         # MetalLB, Traefik
│   ├── security/           # cert-manager, ClusterIssuers
│   ├── observability/      # kube-prometheus-stack, Loki, Alertmanager
│   ├── storage/            # NFS provisioner, StorageClasses
│   ├── backup/             # Velero + MinIO credentials
│   ├── upgrade/            # system-upgrade-controller
│   └── namespaces/         # Namespace declarations
├── apps/                   # Application workloads (base + homelab overlay)
├── ansible/                # Ansible — k3s node provisioning and maintenance
│   ├── inventory/          # homelab.yml — all 3 nodes
│   ├── playbooks/
│   │   ├── lifecycle/      # install-cluster.yml, install-platform.yml, purge-k3s.yml
│   │   ├── security/       # ssh-hardening, firewall, fail2ban, time-sync
│   │   └── maintenance/    # upgrade-nodes.yml, reboot-nodes.yml
│   └── roles/k3s_install/
│
├── raspberry-pi/           # Raspberry Pi control hub (10.0.10.10)
│   ├── README.md
│   ├── ansible/            # RPi setup and tools playbooks
│   ├── scripts/            # backup_rpi.sh
│   └── docs/               # 01_setup, 02_services, 03_backup
│
├── docker/                 # Docker media server (10.0.10.32)
│   ├── README.md
│   ├── compose/            # media-stack.yml, monitoring-stack.yml, proxy-stack.yml
│   ├── config/             # prometheus.yml, loki, promtail, grafana provisioning
│   ├── scripts/            # backup_docker.sh, restore_docker.sh
│   └── docs/               # 01–05 setup guides
│
├── truenas/                # TrueNAS HP MicroServer Gen8 (10.0.10.80)
│   ├── README.md
│   └── docs/               # dataset-layout, nfs-configuration, minio, backblaze-sync
│
└── docs/                   # Cross-cutting documentation
    ├── guides/             # 13-guide deployment series (00–12)
    ├── architecture/       # Platform overview, cluster architecture, networking
    │   └── decisions/      # Architecture Decision Records (ADRs)
    ├── compliance/         # Backup policy, DR plan, security policy
    └── operations/
        └── runbooks/       # Cluster rebuild, node replacement, alert responses
```

---

## CI/CD

| Workflow | Trigger | Purpose |
|---------|---------|---------|
| [validate.yml](.github/workflows/validate.yml) | Push / PR | kubeconform schema validation of all manifests |
| [flux-local.yml](.github/workflows/flux-local.yml) | PR | flux-local diff posted as PR comment |
| [promote-to-prod.yml](.github/workflows/promote-to-prod.yml) | Push to `main` | 4-stage gated pipeline: validate → staging health → promote → prod health |

Health check jobs run on a **self-hosted runner on `bran` (10.0.10.10)**, giving the CI pipeline direct LAN access to both clusters with no third-party VPN dependency. See [ADR-007](docs/adr/ADR-007-self-hosted-runners.md).

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
| [Cluster Rebuild](docs/operations/runbooks/cluster-rebuild.md) | Full recovery procedure — RTO 90–120 min |
| [Node Replacement](docs/operations/runbooks/node-replacement.md) | Replace a failed worker node |
| [Backup Restoration](docs/operations/runbooks/backup-restoration.md) | Velero restore procedures |
| [Certificate Failure](docs/operations/runbooks/certificate-failure.md) | TLS cert troubleshooting |
| [Alert Runbooks](docs/operations/runbooks/alerts/) | Per-alert response procedures |

---

## License

MIT
