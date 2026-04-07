<div align="center">

<img src="https://github.com/user-attachments/assets/cba21e9d-1275-4c92-ab9b-365f31f35add" align="center" width="160px" height="160px"/>

# kagiso.me · homelab-infrastructure

_Infrastructure-as-code for a fully self-hosted homelab — GitOps-reconciled by FluxCD, secrets encrypted with SOPS + age, and observable end-to-end._

</div>

---

<div align="center">

[![k3s](https://img.shields.io/badge/k3s-v1.31-326CE5?style=for-the-badge&logo=kubernetes&logoColor=white)](https://k3s.io)&nbsp;
[![FluxCD](https://img.shields.io/badge/GitOps-FluxCD_v2-5468FF?style=for-the-badge&logo=flux&logoColor=white)](https://fluxcd.io)&nbsp;
[![SOPS](https://img.shields.io/badge/Secrets-SOPS_+_age-7C3AED?style=for-the-badge&logoColor=white)](docs/guides/03-Secrets-Management.md)&nbsp;
[![Prometheus](https://img.shields.io/badge/Monitoring-Prometheus_+_Grafana-E6522C?style=for-the-badge&logo=prometheus&logoColor=white)](docs/guides/09-Monitoring-Observability.md)

</div>

<div align="center">

[![Validate & Health Check](https://github.com/Kagiso-me/homelab-infrastructure/actions/workflows/validate.yml/badge.svg)](https://github.com/Kagiso-me/homelab-infrastructure/actions/workflows/validate.yml)

</div>

<div align="center">

[![Network](https://img.shields.io/badge/Network-10.0.10.0%2F24-22c55e?style=flat-square&logo=ubiquiti&logoColor=white)](#infrastructure)&nbsp;
[![Nodes](https://img.shields.io/badge/k3s_Nodes-3-326CE5?style=flat-square&logo=kubernetes&logoColor=white)](#kubernetes-platform)&nbsp;
[![Backups](https://img.shields.io/badge/Backup_Layers-4-22c55e?style=flat-square)](#backup-strategy)&nbsp;
[![Alerts](https://img.shields.io/badge/Alerts-Discord-5865F2?style=flat-square&logo=discord&logoColor=white)](docs/guides/09-Monitoring-Observability.md)&nbsp;
[![Site](https://img.shields.io/badge/Site-kagiso.me-fab387?style=flat-square)](https://kagiso-me.github.io)

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
                   ┌────────────▼──────────────┐
                   │    Home Network            │
                   │    10.0.10.0/24            │
                   │    DNS: bran (Pi-hole)    │
                   └────────────┬──────────────┘
                                │
        ┌───────────────────────┼───────────────────────┐
        │                       │                       │
┌───────▼──────────┐  ┌─────────▼───────┐  ┌───────────▼──────────┐
│  k3s Cluster     │  │  bronn           │  │  ned                 │
│  3 nodes         │  │  Intel NUC       │  │  HP MicroServer Gen8 │
│  10.0.10.11–13   │  │  10.0.10.20      │  │  10.0.10.80          │
│  VIP 10.0.10.110 │  │  Docker / media  │  │  TrueNAS / NFS / S3  │
└──────────────────┘  └─────────────────┘  └──────────────────────┘
        ▲
        │ kubectl / flux / ansible
┌───────┴──────────┐        ┌──────────────────┐
│  varys            │        │  bran            │
│  Intel NUC        │        │  Raspberry Pi     │
│  10.0.10.10       │        │  10.0.10.9        │
│  Control hub      │        │  Pi-hole / DNS    │
└──────────────────┘        └──────────────────┘
        ▲
        │ SSH
   Your Laptop
```

### Node Inventory

| Hostname | IP | Role | Hardware |
|----------|----|------|----------|
| **tywin** | `10.0.10.11` | k3s control-plane + etcd | Lenovo ThinkCentre M93, i5-4570T, 16GB RAM _(Xeon E3-1230L v3 swap: 2nd May 2026)_ |
| **tyrion** | `10.0.10.12` | k3s control-plane + etcd | Lenovo ThinkCentre M93, i5-4570T, 16GB RAM _(Xeon E3-1230L v3 swap: 2nd May 2026)_ |
| **jaime** | `10.0.10.13` | k3s control-plane + etcd | Lenovo ThinkCentre M93, i5-4570T, 16GB RAM _(Xeon E3-1230L v3 swap: 2nd May 2026)_ |
| **varys** | `10.0.10.10` | Control hub — kubectl, Ansible, GitHub runner | Intel NUC i3-5010U |
| **bronn** | `10.0.10.20` | Docker host — media stack | Intel NUC i3-7100U |
| **ned** | `10.0.10.80` | NAS — NFS, MinIO S3, Backblaze B2 | HP MicroServer Gen8 — Xeon E31260L @ 2.40GHz, 16GB ECC RAM, LSI 9207-8i HBA, 1×8TB SAS + 2×4TB SAS + 2×480GB SSD + 1×128GB SSD (OS) |
| **bran** | `10.0.10.15` | Pi-hole DNS + Unbound, Tailscale exit node | Raspberry Pi |
| **kube-vip** | `10.0.10.100` | Kubernetes API VIP | — |
| **Traefik VIP** | `10.0.10.110` | Ingress load balancer | — |

---

## Kubernetes Platform

All cluster state is declared as YAML and continuously reconciled by FluxCD v2. A merged PR is the only way anything changes in the cluster.

```
git push branch → open PR → CI validates + flux diff → merge → Flux reconciles → health check
```

| Layer | Technology | Detail |
|-------|-----------|--------|
| Orchestration | k3s v1.31 | Lightweight Kubernetes, embedded etcd — 3-node HA control-plane |
| GitOps | FluxCD v2 | Kustomization + HelmRelease controllers |
| Ingress | Traefik v3 | HTTP/HTTPS routing — VIP `10.0.10.110` |
| Load Balancer | MetalLB | Bare-metal ARP mode — pool `10.0.10.110–10.0.10.115` |
| TLS | cert-manager + Let's Encrypt | Wildcard `*.kagiso.me` via DNS-01 Cloudflare |
| Identity | Authentik | SSO — `auth.kagiso.me` |
| Security | CrowdSec | Community threat intelligence + Traefik bouncer |
| Metrics | kube-prometheus-stack | Prometheus + Grafana + Alertmanager |
| Logs | Loki + Promtail | Log aggregation and alerting |
| Backups | Velero + MinIO | PVC snapshot and restore via S3 API |
| Secrets | SOPS + age | Encrypted secrets committed to Git |
| Storage | NFS subdir provisioner | Dynamic PV provisioning via ned NFS |
| Databases | PostgreSQL + Redis | Shared central instances |
| Upgrades | system-upgrade-controller | Automated k3s node upgrades via Plans |

---

## Running Applications

### k3s Cluster

| App | Namespace | URL |
|-----|-----------|-----|
| Vaultwarden | `apps` | `vault.kagiso.me` |
| Immich | `apps` | `photos.kagiso.me` |
| Nextcloud | `apps` | `cloud.kagiso.me` |
| Authentik | `apps` | `auth.kagiso.me` |
| n8n | `apps` | `n8n.kagiso.me` |

### bronn — Docker (`10.0.10.20`)

| App | Port | Description |
|-----|------|-------------|
| Plex | 32400 | Media streaming |
| SABnzbd | 8085 | Usenet downloader |
| Sonarr | 8989 | TV series management |
| Radarr | 7878 | Movie management |
| Lidarr | 8686 | Music management |
| Navidrome | 4533 | Music streaming server |
| Uptime Kuma | 3001 | Service monitoring |
| NPM | 81 | Nginx Proxy Manager |

---

## Backup Strategy

Four independent layers ensure no single failure causes data loss.

```
Layer 1 — Git       Kubernetes manifests + configs     Every commit
Layer 2 — etcd      k3s snapshots → MinIO on ned       Every 6 hours (7 retained)
Layer 3 — Velero    PVC data → MinIO S3 on ned         Daily 03:00 (7d retention)
Layer 4 — Offsite   ned (TrueNAS) → Backblaze B2       Nightly cloud sync (30d retention)
```

varys key material (age key, SSH keys, kubeconfig) is backed up encrypted to ned via NFS.

> Full strategy: [Guide 10 — Backups & Disaster Recovery](docs/guides/10-Backups-Disaster-Recovery.md)

---

## Repository Structure

```
homelab-infrastructure/
│
├── clusters/prod/        # Flux entry points — watches main branch
│
├── platform/             # Cluster-wide platform components (HelmReleases)
│   ├── networking/       # MetalLB, Traefik
│   ├── security/         # cert-manager, Authentik, CrowdSec
│   ├── observability/    # kube-prometheus-stack, Loki, Alertmanager
│   ├── storage/          # NFS provisioner, StorageClasses
│   ├── backup/           # Velero + MinIO credentials
│   ├── databases/        # PostgreSQL + Redis
│   ├── upgrade/          # system-upgrade-controller + Plans
│   └── namespaces/       # Namespace declarations
│
├── apps/                 # Application workloads
│   ├── base/             # Per-app manifests (HelmRelease, IngressRoute, Secret)
│   ├── infrastructure/   # Infrastructure apps
│   ├── media/            # Media apps
│   ├── productivity/     # Productivity apps
│   └── prod/             # Production kustomization — lists active apps
│
├── ansible/              # Node provisioning and maintenance
│   ├── inventory/        # homelab.yml — all nodes
│   └── playbooks/
│       ├── lifecycle/    # install-cluster, purge-k3s
│       ├── security/     # ssh-hardening, firewall, fail2ban
│       ├── maintenance/  # upgrade-nodes, reboot-nodes
│       └── docker/       # deploy.yml — GitOps for bronn
│
├── varys/                # Control hub — scripts, runner config
├── bran/                # bran RPi — Pi-hole, DNS, observer
├── docker/               # bronn — compose stacks and config
├── truenas/              # ned — NFS, MinIO, Backblaze docs
│
├── projects/             # Platform initiatives and dev projects
│
└── docs/
    ├── guides/           # 13-guide deployment series (00–13)
    ├── adr/              # Architecture Decision Records (ADR-001–013)
    ├── architecture/     # Platform overview, networking, storage diagrams
    ├── compliance/       # Backup policy, DR plan, security policy
    ├── ops-log/          # Operational log — dated change records
    └── operations/
        └── runbooks/     # Cluster rebuild, node replacement, alert responses
```

---

## CI/CD Pipeline

| Workflow | Trigger | Runner | Purpose |
|---------|---------|--------|---------|
| `validate.yml` | PR (infra paths) | GitHub-hosted | kubeconform + kustomize build + pluto |
| `validate.yml` | PR (infra paths) | Self-hosted (varys) | `flux diff` posted as PR comment |
| `validate.yml` | Push to `main` | Self-hosted (varys) | Flux reconcile + health check |
| `docker-deploy.yml` | Push to `main` (docker paths) | Self-hosted (varys) | Ansible deploy to bronn |
| `fetch-live-data.yml` | Every 30 min | Self-hosted (varys) | Collect cluster metrics → kagiso-me.github.io |

Self-hosted runners on varys: `~/actions-runner/` (homelab-infrastructure), `~/actions-runner-site/` (site repo). See [ADR-007](docs/adr/ADR-007-self-hosted-runners.md).

---

## Documentation Map

### Architecture Decision Records

| ADR | Decision |
|-----|---------|
| [ADR-001](docs/adr/ADR-001-k3s-over-kubeadm.md) | k3s over kubeadm |
| [ADR-002](docs/adr/ADR-002-flux-over-argocd.md) | FluxCD over ArgoCD |
| [ADR-003](docs/adr/ADR-003-traefik-over-nginx-ingress.md) | Traefik over NGINX Ingress |
| [ADR-007](docs/adr/ADR-007-self-hosted-runners.md) | Self-hosted GitHub Actions runners |
| [ADR-009](docs/adr/ADR-009-prometheus-local-storage.md) | Prometheus local storage |
| [ADR-011](docs/adr/ADR-011-central-databases.md) | Centralised PostgreSQL + Redis |
| [ADR-012](docs/adr/ADR-012-pr-validation-pipeline.md) | PR validation pipeline |
| [ADR-013](docs/adr/ADR-013-site-data-pipeline.md) | Public site live data pipeline |
| [Full index →](docs/adr/) | All ADRs |

### Runbooks

| Document | Description |
|----------|-------------|
| [Cluster Rebuild](docs/operations/runbooks/cluster-rebuild.md) | Full recovery — RTO 90–120 min |
| [Node Replacement](docs/operations/runbooks/node-replacement.md) | Replace a failed cluster node |
| [Backup Restoration](docs/operations/runbooks/backup-restoration.md) | Velero restore procedures |
| [Add GitHub Runner](docs/operations/runbooks/add-github-runner.md) | Register a new self-hosted runner |
| [Alert Runbooks](docs/operations/runbooks/alerts/) | Per-alert response procedures |

### Ops Log

Dated record of every significant change: [docs/ops-log/](docs/ops-log/)

---

## Getting Started

Build in this order — each layer depends on the one before.

```bash
# 1. Provision nodes (from your laptop)
ansible-playbook -i ansible/inventory/homelab.yml \
  ansible/playbooks/security/ssh-hardening.yml \
  ansible/playbooks/security/firewall.yml

# 2. Install k3s
ansible-playbook -i ansible/inventory/homelab.yml \
  ansible/playbooks/lifecycle/install-cluster.yml

# 3. Bootstrap Flux
flux bootstrap github \
  --owner=Kagiso-me \
  --repository=homelab-infrastructure \
  --branch=main \
  --path=clusters/prod \
  --personal

# 4. Deploy bronn (Docker media stack)
ansible-playbook -i ansible/inventory/homelab.yml \
  ansible/playbooks/docker/deploy.yml
```

> Full walkthrough: start at [Guide 00 — Platform Philosophy](docs/guides/00-Platform-Philosophy.md)

---

## License

MIT
