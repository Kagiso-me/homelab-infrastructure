# Docker — Media Server

> **Infrastructure note (2026-03-16):** This host is being converted to a **Proxmox VE
> hypervisor**. The Docker stack will move into a VM (`docker-vm`) running on Proxmox.
> A second VM (`staging-k3s`) will host the staging Kubernetes cluster.
> This directory documents the current bare-metal Docker configuration and will remain
> as a historical reference. See [ADR-006](../docs/architecture/decisions/ADR-006-proxmox-pivot.md)
> and the [ops-log entry](../docs/ops-log/2026-03-16-pivot-nuc-to-proxmox.md) for context.

**Hostname:** `docked`
**IP:** `10.0.10.20`

**OS:** Ubuntu Server 22.04 LTS
**Role:** Self-hosted media stack running as Docker containers

---

## Access Model

This host is **not accessed directly** from your laptop. All SSH sessions go through the Raspberry Pi:

```
Laptop → Raspberry Pi (10.0.10.80) → Docker host (10.0.10.20)
```

```bash
# From the RPi
ssh kagiso@10.0.10.20
```

This keeps the media server off the direct-access list and centralises management through the control hub.

---

## Media Stack

| Service | Purpose | Port / URL |
|---------|---------|-----------|
| Jellyfin | Media server (movies, TV, music) | http://10.0.10.20:8096 |
| Sonarr | TV show automation | http://10.0.10.20:8989 |
| Radarr | Movie automation | http://10.0.10.20:7878 |
| Prowlarr | Indexer management | http://10.0.10.20:9696 |
| qBittorrent | Download client | http://10.0.10.20:8080 |
| Nginx Proxy Manager | Reverse proxy + SSL | http://10.0.10.20:81 |
| Portainer | Docker management UI | http://10.0.10.20:9000 |
| Watchtower | Automatic container updates | *(runs on schedule)* |

> Update this table to match your actual running services.

---

## Storage Layout

```
/mnt/media/              ← media library (NFS from TrueNAS or local disk)
├── movies/
├── tv/
└── music/

/opt/docker/             ← container config and data
├── jellyfin/
├── sonarr/
├── radarr/
├── prowlarr/
└── nginx-proxy-manager/
```

---

## Relationship to TrueNAS

Media files optionally live on TrueNAS via NFS mount:

```bash
# /etc/fstab entry on the docker host (if using NFS for media)
10.0.10.80:/mnt/tera /mnt/media nfs defaults,_netdev 0 0
```

This keeps media off the Docker host disk and allows TrueNAS snapshots to protect the library.

---

## Backups

Container configs are backed up by `scripts/backup_docker.sh`:

```bash
# Run manually or schedule via cron
./scripts/backup_docker.sh
```

This tarballs `/opt/docker/` and copies the archive to TrueNAS NFS. Restore with `scripts/restore_docker.sh`.

See [docs/05_backups_and_disaster_recovery.md](docs/05_backups_and_disaster_recovery.md) for the full backup strategy.

---

## Directory Structure

```
docker/
├── README.md               # this file
├── compose/                # docker-compose.yml files per service
├── docs/
│   ├── 00_plan.md          # design decisions
│   ├── 01_host_installation_and_hardening.md
│   ├── 02_docker_installation_and_filesystem.md
│   ├── 03_media_stack_and_reverse_proxy.md
│   ├── 04_monitoring_and_logging.md
│   └── 05_backups_and_disaster_recovery.md
└── scripts/
    ├── backup_docker.sh
    └── restore_docker.sh
```

---

## Why Docker and Not Kubernetes

The media stack runs on Docker rather than Kubernetes for these reasons:

1. **Privileged hardware access** — Jellyfin needs direct access to GPU/iGPU for transcoding. Kubernetes GPU passthrough is complex and fragile on k3s without the NVIDIA device plugin stack.
2. **Simpler networking** — Download clients, indexers, and VPN containers have complex networking requirements that are easier to manage with Docker networks than Kubernetes CNI.
3. **Isolation** — Keeping untrusted download traffic physically separated from the k3s cluster is a deliberate security choice.

See [docs/00_plan.md](docs/00_plan.md) for the full design rationale.
