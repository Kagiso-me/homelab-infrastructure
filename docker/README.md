# Docker — Media Server

**Hostname:** `bronn`
**IP:** `10.0.10.20`

**Hardware:** Intel NUC i3-7100U — 16 GB RAM, 256 GB NVMe
**OS:** Ubuntu Server 22.04 LTS
**Role:** Self-hosted media acquisition and streaming stack running as Docker containers

---

## Access Model

SSH directly from your laptop or from varys:

```bash
# From your laptop (via Tailscale or LAN)
ssh kagiso@10.0.10.20

# Or via varys if needed
ssh -J kagiso@10.0.10.10 kagiso@10.0.10.20
```

---

## Media Stack

| Service | Purpose | Port / URL |
|---------|---------|-----------|
| Plex | Media server (movies, TV, music) | http://10.0.10.20:32400 |
| Sonarr | TV show automation | http://10.0.10.20:8989 |
| Radarr | Movie automation | http://10.0.10.20:7878 |
| Lidarr | Music automation | http://10.0.10.20:8686 |
| Prowlarr | Indexer management | http://10.0.10.20:9696 |
| Overseerr | Media request management | http://10.0.10.20:5055 |
| SABnzbd | Usenet download client | http://10.0.10.20:8085 |
| Bazarr | Subtitle management | http://10.0.10.20:6767 |
| Navidrome | Music streaming server | http://10.0.10.20:4533 |
| Nginx Proxy Manager | Reverse proxy + TLS (Let's Encrypt DNS-01) | http://10.0.10.20:81 |
| Node Exporter | Prometheus metrics for this host | http://10.0.10.20:9100 |
| cAdvisor | Container metrics | http://10.0.10.20:8080 |

---

## Storage Layout

```
/mnt/media/              ← media library (NFS from TrueNAS)
├── movies/
├── tv/
├── music/
└── downloads/

/srv/docker/             ← container config and persistent data
├── stacks/              ← compose files (synced from Git by Ansible)
│   ├── media-stack.yml
│   ├── proxy-stack.yml
│   └── monitoring-stack.yml
└── data/                ← app data volumes (plex, sonarr, etc.)
```

---

## GitOps Model

Docker compose files live in `docker/compose/` in this repo. A push to `main` that touches `docker/compose/**` or `docker/config/**` triggers the `docker-deploy` GitHub Actions workflow, which runs an Ansible playbook to sync and reconcile the stacks on bronn.

```bash
# Manual deploy (from varys or your laptop)
cd ~/homelab-infrastructure/ansible
ansible-playbook -i inventory/homelab.yml \
  playbooks/docker/deploy.yml

# Deploy a single stack
ansible-playbook -i inventory/homelab.yml \
  playbooks/docker/deploy.yml \
  -e target_stack=media-stack
```

Secrets (`.env` file with API keys, Plex claim token, etc.) stay on the host at `/srv/docker/.env` and are never committed to Git.

---

## Relationship to TrueNAS

Media files live on TrueNAS via NFS:

```bash
# /etc/fstab entry on bronn
10.0.10.80:/mnt/tera/media /mnt/media nfs defaults,_netdev 0 0
```

TrueNAS snapshots protect the media library. Container config data is backed up separately.

---

## Why Docker and Not Kubernetes

The media stack runs on Docker rather than Kubernetes for these reasons:

1. **Privileged hardware access** — Plex needs direct iGPU access for hardware transcoding. Kubernetes GPU passthrough on k3s requires the Intel device plugin stack and is significantly more complex.
2. **Simpler networking** — Download clients, indexers, and VPN containers have networking requirements that are easier to manage with Docker bridge networks than Kubernetes CNI.
3. **Isolation** — Keeping untrusted download traffic physically separated from the k3s cluster is a deliberate security choice.

---

## Directory Structure

```
docker/
├── README.md               # this file
├── compose/                # docker-compose.yml files per stack
│   ├── media-stack.yml
│   ├── proxy-stack.yml
│   └── monitoring-stack.yml
└── docs/
    ├── 00_plan.md
    ├── 01_host_installation_and_hardening.md
    ├── 02_docker_installation_and_filesystem.md
    ├── 03_media_stack_and_reverse_proxy.md
    ├── 04_monitoring_and_logging.md
    └── 05_backups_and_disaster_recovery.md
```
