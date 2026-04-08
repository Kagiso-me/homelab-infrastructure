# bronn — Docker Media Server

**Hostname:** `bronn`
**IP:** `10.0.10.20`
**Hardware:** Intel NUC i3-7100U — 16 GB RAM, 256 GB NVMe
**OS:** Ubuntu Server 22.04 LTS

---

## The Character

<div align="center">

<!-- Photo placeholder: Bronn (Jerome Flynn) from Game of Thrones -->
> _📸 Photo coming soon — Bronn_

</div>

**Bronn** is a sellsword — a mercenary who doesn't care about honour or titles. He takes on the jobs nobody else wants to do, he does them efficiently, and he asks no questions. Need something acquired? Bronn handles it. Need it delivered? Done. He's not part of the noble houses, he doesn't run the kingdom, but without him a lot of things simply wouldn't get done.

**Why this machine:** `bronn` does the dirty work of the homelab. It acquires content (SABnzbd, Sonarr, Radarr, Lidarr), organises it, and streams it (Plex, Navidrome). No glory, no Kubernetes orchestration — just Docker containers running bare metal, getting the job done. Like the character, bronn operates outside the "proper" system (k3s) and is better for it.

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
/mnt/media/              ← media library (NFS from TrueNAS — 10.0.10.80)
├── movies/
├── tv/
└── music/

/mnt/downloads/          ← completed downloads (NFS from TrueNAS)
└── complete/

/mnt/archive/            ← backup destination (NFS: 10.0.10.80:/mnt/archive/backups)

/srv/docker/             ← container config and persistent data
├── compose/             ← compose files (synced from Git)
│   ├── media-stack.yml
│   ├── proxy-stack.yml
│   ├── platform-stack.yml
│   └── monitoring-exporters.yml
├── downloads/
│   └── incomplete/      ← in-progress downloads (local NVMe, fast writes)
└── appdata/             ← per-service config volumes (plex, sonarr, etc.)
```

> **NFS mount note:** Despite `_netdev` in fstab, mounts do not always auto-apply on boot. After a reboot, run `sudo mount -a` if `/mnt/media` or `/mnt/downloads` appear empty.

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

Secrets (`.env` file with API keys, Plex claim token, etc.) stay on the host at `/srv/docker/compose/.env` and are never committed to Git.

---

## Relationship to TrueNAS

Media files and downloads live on TrueNAS via NFS:

```bash
# /etc/fstab entries on bronn
10.0.10.80:/mnt/tera/media      /mnt/media      nfs _netdev,hard,noatime,rsize=131072,wsize=131072,timeo=14,tcp 0 0
10.0.10.80:/mnt/tera/downloads  /mnt/downloads  nfs _netdev,hard,noatime,rsize=131072,wsize=131072,timeo=14,tcp 0 0
10.0.10.80:/mnt/archive/backups /mnt/archive    nfs _netdev,hard,noatime,rsize=131072,wsize=131072,timeo=14,tcp 0 0
```

> **Note:** These mounts do not always auto-apply on boot. Run `sudo mount -a` after a reboot if they are not active.

TrueNAS snapshots protect the media library. Container config data is backed up separately via Restic.

---

## Why Docker and Not Kubernetes

The media stack runs on Docker rather than Kubernetes for these reasons:

1. **Privileged hardware access** — Plex needs direct iGPU access for hardware transcoding. Kubernetes GPU passthrough on k3s requires the Intel device plugin stack and is significantly more complex.
2. **Simpler networking** — Download clients, indexers, and VPN containers have networking requirements that are easier to manage with Docker bridge networks than Kubernetes CNI.
3. **Isolation** — Keeping untrusted download traffic physically separated from the k3s cluster is a deliberate security choice.

---

## Directory Structure

```
bronn/
├── README.md               # this file
├── compose/                # docker-compose.yml files per stack
│   ├── media-stack.yml
│   ├── proxy-stack.yml
│   ├── platform-stack.yml
│   └── monitoring-exporters.yml
├── config/
│   └── promtail/           # promtail config (log shipping to k3s Loki)
└── docs/
    ├── 00_plan.md
    ├── 01_host_installation_and_hardening.md
    ├── 02_docker_installation_and_filesystem.md
    ├── 03_media_stack_and_reverse_proxy.md
    ├── 04_monitoring_and_logging.md
    └── 05_backups_and_disaster_recovery.md
```
