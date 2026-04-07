# Docker Media Server Ã¢â‚¬â€ Homelab Handbook

**Author:** Kagiso Tjeane
**Version:** 2.0
**Last updated:** 2026-03-14

> Infrastructure that cannot be rebuilt easily is broken infrastructure.
>
> This handbook documents every decision, every component, and every recovery procedure for the Docker-based media server. A fresh host can be fully restored using only this repository and access to TrueNAS.

---

## Core Philosophy

The homelab media server is built on five non-negotiable principles:

| Principle | Implementation |
|-----------|---------------|
| **1 Ã¢â‚¬â€ The host is disposable** | No application state lives on the Docker host disk. All persistent data lives on TrueNAS. |
| **2 Ã¢â‚¬â€ Storage outlives compute** | Media library and downloads live on TrueNAS NFS mounts. The host can be wiped and rebuilt without data loss. |
| **3 Ã¢â‚¬â€ Configuration lives in Git** | Every compose file, every config template, every script lives in this repository. |
| **4 Ã¢â‚¬â€ Observability is not optional** | Prometheus + Grafana + Loki + Node Exporter run from day one. You cannot manage what you cannot observe. |
| **5 Ã¢â‚¬â€ Recovery must be predictable** | The rebuild procedure is documented, tested, and achieves a running stack in under 90 minutes. |

These principles exist because homelab systems tend to accumulate undocumented complexity. A past incident Ã¢â‚¬â€ an `rm -rf` accident that corrupted the running system Ã¢â‚¬â€ exposed what happens when infrastructure is organic rather than designed. This system was rebuilt from scratch with reproducibility as the primary goal.

---

## System Architecture

```mermaid
graph TD
    Internet["Internet"] --> Router["Home Router\n10.0.0.1"]
    Router --> NPM["Nginx Proxy Manager\n10.0.10.20:80/443\nReverse proxy + TLS"]
    NPM --> Jellyfin["Jellyfin\n:8096\nMedia streaming"]
    NPM --> Overseerr["Overseerr\n:5055\nMedia requests"]
    NPM --> Grafana["Grafana\n:3000\nMonitoring"]
    NPM --> Other["Other services\nSonarr, Radarr,\nNavidrome..."]

    subgraph DockerHost["Docker Host Ã¢â‚¬â€ 10.0.10.20"]
        NPM
        Jellyfin
        Overseerr
        Grafana
        Other
        subgraph MediaPipeline["Media Automation"]
            Sonarr["Sonarr (TV)"]
            Radarr["Radarr (Movies)"]
            Prowlarr["Prowlarr (Indexers)"]
            SABnzbd["SABnzbd (Downloads)"]
        end
        subgraph Observability["Observability"]
            Prometheus["Prometheus"]
            Loki["Loki"]
            Promtail["Promtail"]
        end
    end

    DockerHost --> TrueNAS["TrueNAS Ã¢â‚¬â€ 10.0.10.80\nNFS: /mnt/media\nNFS: /mnt/downloads\nBackup target"]
```

---

## Media Pipeline

```mermaid
sequenceDiagram
    participant U as User
    participant O as Overseerr
    participant S as Sonarr/Radarr
    participant P as Prowlarr
    participant SAB as SABnzbd
    participant TN as TrueNAS (NFS)
    participant J as Jellyfin

    U->>O: Request movie/TV show
    O->>S: Forward request
    S->>P: Search indexers
    P-->>S: Available releases
    S->>SAB: Download release
    SAB->>TN: Save to /mnt/downloads/complete
    S->>TN: Import to /mnt/media/movies|tv
    TN-->>J: Media available
    J-->>U: Stream
```

---

## Node Map

```
Your Laptop
    Ã¢â€â€š
    Ã¢â€“Â¼ SSH
bran Ã¢â‚¬â€ 10.0.10.10 (control hub)
    Ã¢â€â€š
    Ã¢â€“Â¼ SSH
Docker Host Ã¢â‚¬â€ 10.0.10.20
    Ã¢â€â€š
    Ã¢â€Å“Ã¢â€â‚¬Ã¢â€â‚¬ /mnt/media         Ã¢â€ Â NFS from TrueNAS /mnt/tera
    Ã¢â€Å“Ã¢â€â‚¬Ã¢â€â‚¬ /mnt/downloads     Ã¢â€ Â NFS from TrueNAS /mnt/tera
    Ã¢â€â€Ã¢â€â‚¬Ã¢â€â‚¬ /mnt/archive          Ã¢â€ Â NFS from TrueNAS (backup destination)

TrueNAS Ã¢â‚¬â€ 10.0.10.80
    Ã¢â€â€Ã¢â€â‚¬Ã¢â€â‚¬ ZFS pools: core, archive, tera
        Ã¢â€Å“Ã¢â€â‚¬Ã¢â€â‚¬ media/
        Ã¢â€Å“Ã¢â€â‚¬Ã¢â€â‚¬ downloads/
        Ã¢â€â€Ã¢â€â‚¬Ã¢â€â‚¬ backups/docker/     Ã¢â€ Â Docker appdata backups land here
```

---

## Stacks and Services

### Media Stack (`compose/media-stack.yml`)

| Service | Port | Purpose |
|---------|------|---------|
| Jellyfin | 8096 | Media server Ã¢â‚¬â€ streams movies, TV, music |
| Sonarr | 8989 | TV show automation Ã¢â‚¬â€ monitor, download, rename |
| Radarr | 7878 | Movie automation Ã¢â‚¬â€ monitor, download, rename |
| Lidarr | 8686 | Music automation |
| Prowlarr | 9696 | Indexer manager Ã¢â‚¬â€ feeds Sonarr/Radarr/Lidarr |
| Overseerr | 5055 | User-facing request portal |
| SABnzbd | 8080 | Usenet download client |
| Bazarr | 6767 | Subtitle management |
| Navidrome | 4533 | Music streaming server |

### Monitoring Stack (`compose/monitoring-stack.yml`)

| Service | Port | Purpose |
|---------|------|---------|
| Prometheus | 9090 | Metrics collection (15d retention) |
| Grafana | 3000 | Dashboards and alerting |
| Node Exporter | Ã¢â‚¬â€ | Host metrics (CPU, RAM, disk, network) |
| cAdvisor | 8081 | Container-level metrics |
| Loki | 3100 | Log aggregation |
| Promtail | Ã¢â‚¬â€ | Log collection agent |

### Proxy Stack (`compose/proxy-stack.yml`)

| Service | Ports | Purpose |
|---------|-------|---------|
| Nginx Proxy Manager | 80, 81, 443 | Reverse proxy, SSL termination, Let's Encrypt |

---

## Directory Structure

```
/srv/
Ã¢â€Å“Ã¢â€â‚¬Ã¢â€â‚¬ docker/
Ã¢â€â€š   Ã¢â€Å“Ã¢â€â‚¬Ã¢â€â‚¬ appdata/           Ã¢â€ Â ALL application state Ã¢â‚¬â€ this is what gets backed up
Ã¢â€â€š   Ã¢â€â€š   Ã¢â€Å“Ã¢â€â‚¬Ã¢â€â‚¬ jellyfin/
Ã¢â€â€š   Ã¢â€â€š   Ã¢â€Å“Ã¢â€â‚¬Ã¢â€â‚¬ sonarr/
Ã¢â€â€š   Ã¢â€â€š   Ã¢â€Å“Ã¢â€â‚¬Ã¢â€â‚¬ radarr/
Ã¢â€â€š   Ã¢â€â€š   Ã¢â€Å“Ã¢â€â‚¬Ã¢â€â‚¬ prowlarr/
Ã¢â€â€š   Ã¢â€â€š   Ã¢â€Å“Ã¢â€â‚¬Ã¢â€â‚¬ sabnzbd/
Ã¢â€â€š   Ã¢â€â€š   Ã¢â€Å“Ã¢â€â‚¬Ã¢â€â‚¬ overseerr/
Ã¢â€â€š   Ã¢â€â€š   Ã¢â€Å“Ã¢â€â‚¬Ã¢â€â‚¬ grafana/
Ã¢â€â€š   Ã¢â€â€š   Ã¢â€Å“Ã¢â€â‚¬Ã¢â€â‚¬ prometheus/
Ã¢â€â€š   Ã¢â€â€š   Ã¢â€Å“Ã¢â€â‚¬Ã¢â€â‚¬ loki/
Ã¢â€â€š   Ã¢â€â€š   Ã¢â€Å“Ã¢â€â‚¬Ã¢â€â‚¬ promtail/
Ã¢â€â€š   Ã¢â€â€š   Ã¢â€â€Ã¢â€â‚¬Ã¢â€â‚¬ npm/
Ã¢â€â€š   Ã¢â€â€Ã¢â€â‚¬Ã¢â€â‚¬ stacks/            Ã¢â€ Â compose files (symlinks or copies from this repo)
Ã¢â€Å“Ã¢â€â‚¬Ã¢â€â‚¬ downloads/
Ã¢â€â€š   Ã¢â€Å“Ã¢â€â‚¬Ã¢â€â‚¬ incomplete/        Ã¢â€ Â SABnzbd active downloads (safe to delete)
Ã¢â€â€š   Ã¢â€â€Ã¢â€â‚¬Ã¢â€â‚¬ complete/          Ã¢â€ Â completed downloads pending import (safe to delete)
Ã¢â€â€Ã¢â€â‚¬Ã¢â€â‚¬ scripts/
    Ã¢â€â€Ã¢â€â‚¬Ã¢â€â‚¬ backup_docker.sh

/mnt/
Ã¢â€Å“Ã¢â€â‚¬Ã¢â€â‚¬ media/                 Ã¢â€ Â NFS from TrueNAS Ã¢â‚¬â€ media library (DO NOT delete)
Ã¢â€â€š   Ã¢â€Å“Ã¢â€â‚¬Ã¢â€â‚¬ movies/
Ã¢â€â€š   Ã¢â€Å“Ã¢â€â‚¬Ã¢â€â‚¬ tv/
Ã¢â€â€š   Ã¢â€â€Ã¢â€â‚¬Ã¢â€â‚¬ music/
Ã¢â€Å“Ã¢â€â‚¬Ã¢â€â‚¬ downloads/             Ã¢â€ Â NFS from TrueNAS Ã¢â‚¬â€ imported downloads
Ã¢â€â€Ã¢â€â‚¬Ã¢â€â‚¬ archive/              Ã¢â€ Â NFS from TrueNAS (archive pool) Ã¢â‚¬â€ backup destination
```

---

## Backup Strategy

```
Layer 1 Ã¢â‚¬â€ Git             Compose files, scripts, config templates   Always current (automatic)
Layer 2 Ã¢â‚¬â€ appdata         /srv/docker/appdata Ã¢â€ â€™ TrueNAS              Daily 02:00, 7-day retention
Layer 3 Ã¢â‚¬â€ Media library   TrueNAS ZFS snapshots                      Hourly/daily/weekly
Layer 4 Ã¢â‚¬â€ Offsite         TrueNAS Ã¢â€ â€™ Backblaze B2                     Nightly (30-day retention)
```

The most critical backup is **Layer 2** Ã¢â‚¬â€ the appdata directory. This contains:
- Jellyfin metadata, watched status, user preferences
- Sonarr/Radarr databases (series/movie lists, history)
- SABnzbd configuration and history
- Grafana dashboards and alert configurations
- Nginx Proxy Manager proxy host configs and certificates

Media files themselves (movies, TV, music) live on TrueNAS and are protected by ZFS snapshots Ã¢â‚¬â€ they are never touched by the Docker backup.

See [docs/05_backups_and_disaster_recovery.md](docs/05_backups_and_disaster_recovery.md) for the complete backup and DR procedure.

---

## Disaster Recovery

**Target RTO: 45Ã¢â‚¬â€œ90 minutes** from bare metal to full stack running.

```
Step 1 Ã¢â‚¬â€ Reinstall Ubuntu Server                    ~15 min
Step 2 Ã¢â‚¬â€ SSH hardening, UFW, Fail2Ban               ~10 min (Guide 02)
Step 3 Ã¢â‚¬â€ Install Docker, mount NFS shares           ~10 min (Guide 03)
Step 4 Ã¢â‚¬â€ Restore appdata from TrueNAS backup        ~5 min
Step 5 Ã¢â‚¬â€ Deploy stacks (proxy Ã¢â€ â€™ media Ã¢â€ â€™ monitoring) ~10 min
Step 6 Ã¢â‚¬â€ Verify all services healthy                ~10 min
Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬
Total                                               ~60 min
```

Full procedure: [docs/05_backups_and_disaster_recovery.md](docs/05_backups_and_disaster_recovery.md)

---

## Guide Series

| Guide | Topic |
|-------|-------|
| [01 Ã¢â‚¬â€ Platform Philosophy](docs/00_plan.md) | Design principles and architecture |
| [02 Ã¢â‚¬â€ Host Installation & Hardening](docs/01_host_installation_and_hardening.md) | Ubuntu, SSH, UFW, Fail2Ban |
| [03 Ã¢â‚¬â€ Docker & Filesystem](docs/02_docker_installation_and_filesystem.md) | Docker install, NFS mounts, directory layout |
| [04 Ã¢â‚¬â€ Media Stack & Reverse Proxy](docs/03_media_stack_and_reverse_proxy.md) | Jellyfin, Sonarr, Radarr, NPM |
| [05 Ã¢â‚¬â€ Monitoring & Logging](docs/04_monitoring_and_logging.md) | Prometheus, Grafana, Loki |
| [06 Ã¢â‚¬â€ Backups & Disaster Recovery](docs/05_backups_and_disaster_recovery.md) | Backup strategy, DR procedure |

---

## Relationship to Kubernetes Platform

This Docker host is intentionally **separate** from the k3s Kubernetes cluster. The decision to keep the media stack on Docker rather than Kubernetes is documented in [docs/00_plan.md](docs/00_plan.md#why-docker-not-kubernetes).

The two systems share TrueNAS as a common storage backend but are otherwise fully independent. A failure in the Kubernetes cluster has no effect on media services, and vice versa.

The bran at `10.0.10.10` serves as the management plane for both Ã¢â‚¬â€ see [bran/README.md](../bran/README.md).
