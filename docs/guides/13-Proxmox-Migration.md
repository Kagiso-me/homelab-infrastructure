# Guide 13 — Proxmox Migration (NUC Docker Host → Proxmox Hypervisor)

> **Status:** In progress — 2026-03-16
> **Ops-log:** [2026-03-16-pivot-nuc-to-proxmox.md](../ops-log/2026-03-16-pivot-nuc-to-proxmox.md)
> **ADR:** [ADR-006-proxmox-pivot.md](../architecture/decisions/ADR-006-proxmox-pivot.md)

This guide documents the migration of the Intel NUC NUC7i3BNH from a bare Docker host
to a Proxmox VE hypervisor hosting two VMs — a Docker workload VM and a staging k3s cluster.

---

## Table of Contents

1. [Overview](#overview)
2. [Pre-Migration Checklist](#pre-migration-checklist)
3. [Step 1 — Backup Docker Host](#step-1--backup-docker-host)
4. [Step 2 — Install Proxmox VE](#step-2--install-proxmox-ve)
5. [Step 3 — Create docker-vm](#step-3--create-docker-vm)
6. [Step 4 — Restore Docker Stack](#step-4--restore-docker-stack)
7. [Step 5 — Create staging-k3s VM](#step-5--create-staging-k3s-vm)
8. [Step 6 — Bootstrap Flux on Staging](#step-6--bootstrap-flux-on-staging)
9. [Step 7 — Enable Staging Promotion Gate](#step-7--enable-staging-promotion-gate)
10. [Post-Migration — Consolidate Monitoring](#post-migration--consolidate-monitoring)
11. [Post-RAM Upgrade — Expand VM Resources](#post-ram-upgrade--expand-vm-resources)
12. [Rollback](#rollback)

---

## Overview

### Before

```
NUC (bare Ubuntu 22.04) — 10.0.10.20
└── Docker Compose
    ├── Prometheus + Grafana + Loki + Alertmanager
    └── Sonarr, Radarr, Plex (+ arr stack)
```

### After

```
NUC (Proxmox VE) — 10.0.10.20
├── docker-vm       — 10.0.10.21 (2 vCPU, 8GB RAM, 80GB)
│   └── Docker Compose
│       ├── Prometheus + Grafana + Loki + Alertmanager
│       └── Sonarr, Radarr, Plex (+ arr stack)
└── staging-k3s     — 10.0.10.22 (2 vCPU, 6GB RAM, 60GB)
    └── k3s single-node
        └── Flux → clusters/staging/ → apps/staging/
```

### VM Resource Allocation

| | Proxmox host | docker-vm | staging-k3s | Total |
|---|---|---|---|---|
| **RAM (16GB now)** | ~2GB | 8GB | 6GB | 16GB |
| **RAM (32GB after upgrade)** | ~2GB | 12GB | 10GB | ~24GB |
| **vCPU** | — | 2 | 2 | 4 threads |
| **Disk** | ~40GB | 80GB | 60GB | ~180GB |

> NFS mounts (TrueNAS `tera/media`, `tera/downloads`, `archive/docker-backups`) move
> from the bare NUC to `docker-vm`. No data migration required — TrueNAS is untouched.

---

## Pre-Migration Checklist

Before touching the NUC, confirm the following:

- [ ] TrueNAS `archive/docker-backups` dataset is accessible and has free space
- [ ] You have the Docker compose files committed in this repo (under `docker/`)
- [ ] Note any volumes with state that aren't in TrueNAS (Grafana dashboards, Prometheus data)
- [ ] Proxmox VE ISO downloaded: https://www.proxmox.com/en/downloads
- [ ] USB drive (8GB+) ready for Proxmox installer
- [ ] SSH access to RPi (10.0.10.10) confirmed — this is your control hub during the outage

---

## Step 1 — Backup Docker Host

From the NUC (`ssh kagiso@10.0.10.20`):

```bash
# 1. Mount the TrueNAS backup share if not already mounted
sudo mkdir -p /mnt/archive
sudo mount -t nfs 10.0.10.80:/mnt/archive /mnt/archive

# 2. Create a timestamped backup directory
BACKUP_DIR="/mnt/archive/docker-backups/pre-proxmox-$(date +%Y%m%d)"
sudo mkdir -p "$BACKUP_DIR"

# 3. Backup Docker volumes
sudo docker ps -q | xargs docker inspect --format '{{ .Name }}' | while read name; do
  echo "Backing up $name..."
done

# 4. Backup all compose files and configs
sudo tar czf "$BACKUP_DIR/docker-compose-backup.tar.gz" \
  ~/docker/ \
  /etc/docker/ \
  2>/dev/null

# 5. Export named volumes
sudo tar czf "$BACKUP_DIR/docker-volumes.tar.gz" /var/lib/docker/volumes/

# 6. Verify backup
ls -lah "$BACKUP_DIR"
```

> Grafana dashboards, Prometheus TSDB, and any persistent app state are in Docker volumes.
> The tar above captures them all. Media files are on TrueNAS and untouched.

---

## Step 2 — Install Proxmox VE

1. **Flash Proxmox VE ISO** to USB (use Rufus on Windows or `dd` on Linux)

2. **Boot NUC from USB** — press F10 at boot for boot menu on ThinkCentre-era NUCs

3. **Installer settings:**
   - Target disk: the 256GB NVMe
   - Hostname: `nuc.homelab`
   - IP: `10.0.10.20` (same as before — keeps DNS/NFS exports working)
   - Gateway: `10.0.10.1`
   - DNS: `10.0.10.1`
   - Root password: use a strong password, save it somewhere safe

4. **First login** — Proxmox web UI at `https://10.0.10.20:8006`

5. **Disable enterprise repo** (no subscription):
   ```bash
   # SSH to Proxmox host
   ssh root@10.0.10.20

   # Disable enterprise repo, enable no-subscription repo
   echo "deb http://download.proxmox.com/debian/pve bookworm pve-no-subscription" \
     > /etc/apt/sources.list.d/pve-community.list
   sed -i 's/^deb/#deb/' /etc/apt/sources.list.d/pve-enterprise.list
   apt update && apt dist-upgrade -y
   ```

---

## Step 3 — Create docker-vm

From the Proxmox web UI or via CLI:

```bash
# Upload Ubuntu 22.04 cloud image or ISO to Proxmox storage first, then:

qm create 100 \
  --name docker-vm \
  --memory 8192 \
  --cores 2 \
  --net0 virtio,bridge=vmbr0 \
  --ide2 local:iso/ubuntu-22.04-live-server.iso,media=cdrom \
  --scsi0 local-lvm:80 \
  --boot order=ide2 \
  --ostype l26

qm start 100
```

**During Ubuntu install:**
- Hostname: `docker-vm`
- IP: `10.0.10.21` (static)
- Username: `kagiso`
- Enable SSH

**After install — install Docker:**
```bash
ssh kagiso@10.0.10.21

curl -fsSL https://get.docker.com | sudo bash
sudo usermod -aG docker kagiso
```

---

## Step 4 — Restore Docker Stack

```bash
ssh kagiso@10.0.10.21

# Mount TrueNAS NFS shares
sudo mkdir -p /mnt/media /mnt/downloads /mnt/archive
echo "10.0.10.80:/mnt/tera/media    /mnt/media    nfs  defaults,_netdev  0 0" | sudo tee -a /etc/fstab
echo "10.0.10.80:/mnt/tera          /mnt/downloads nfs  defaults,_netdev  0 0" | sudo tee -a /etc/fstab
echo "10.0.10.80:/mnt/archive       /mnt/archive   nfs  defaults,_netdev  0 0" | sudo tee -a /etc/fstab
sudo mount -a

# Restore compose files from backup
BACKUP_DIR="/mnt/archive/docker-backups/pre-proxmox-$(date +%Y%m%d)"
sudo tar xzf "$BACKUP_DIR/docker-compose-backup.tar.gz" -C /

# Restore volumes
sudo tar xzf "$BACKUP_DIR/docker-volumes.tar.gz" -C /

# Start all services
cd ~/docker
docker compose up -d
```

**Verify:**
```bash
docker ps
curl -s http://localhost:3000  # Grafana
curl -s http://localhost:9090  # Prometheus
```

---

## Step 5 — Create staging-k3s VM

```bash
# From Proxmox host
qm create 101 \
  --name staging-k3s \
  --memory 6144 \
  --cores 2 \
  --net0 virtio,bridge=vmbr0 \
  --ide2 local:iso/ubuntu-22.04-live-server.iso,media=cdrom \
  --scsi0 local-lvm:60 \
  --boot order=ide2 \
  --ostype l26

qm start 101
```

**During Ubuntu install:**
- Hostname: `staging`
- IP: `10.0.10.22` (static)
- Username: `kagiso`
- Enable SSH

**Install k3s (single-node, no HA needed for staging):**
```bash
ssh kagiso@10.0.10.22

curl -sfL https://get.k3s.io | sh -s - \
  --disable traefik \
  --write-kubeconfig-mode 644

# Verify
kubectl get nodes
```

---

## Step 6 — Bootstrap Flux on Staging

From the RPi (`ssh kagiso@10.0.10.10`):

```bash
# Copy kubeconfig from staging node
scp kagiso@10.0.10.22:/etc/rancher/k3s/k3s.yaml ~/.kube/staging-config
# Update server address
sed -i 's/127.0.0.1/10.0.10.22/' ~/.kube/staging-config

export KUBECONFIG=~/.kube/staging-config

# Bootstrap Flux pointing at the staging path on main branch
flux bootstrap github \
  --owner=Kagiso-me \
  --repository=homelab-infrastructure \
  --branch=main \
  --path=clusters/staging \
  --personal
```

**Verify:**
```bash
flux get kustomizations
flux get helmreleases -A
```

---

## Step 7 — Enable Staging Promotion Gate

Once staging is healthy, uncomment the staging health check in the promotion workflow:

In [`.github/workflows/promote-to-prod.yml`](../../.github/workflows/promote-to-prod.yml),
find the `staging-health` job and remove the placeholder comments. Then add the
`STAGING_KUBECONFIG` secret to the GitHub repo:

```bash
# From RPi — encode staging kubeconfig
cat ~/.kube/staging-config | base64 | tr -d '\n'
```

Add as a GitHub Actions secret named `STAGING_KUBECONFIG`.

---

## Post-Migration — Consolidate Monitoring

With the Proxmox migration complete, the Docker monitoring stack is redundant.
The k3s kube-prometheus-stack should be extended to scrape all external targets:

- Proxmox host node exporter (`10.0.10.20:9100`)
- docker-vm node exporter (`10.0.10.21:9100`)
- TrueNAS SNMP / node exporter (`10.0.10.80`)
- RPi node exporter (`10.0.10.10:9100`)

Then decommission the Docker monitoring stack (remove from docker-compose).

> See Guide 05 (Monitoring) for `additionalScrapeConfigs` implementation.

---

## Post-RAM Upgrade — Expand VM Resources

After installing 32GB DDR4 SO-DIMM (~2026-03-23):

```bash
# Shut down VMs, resize from Proxmox host
qm shutdown 100
qm set 100 --memory 12288
qm start 100

qm shutdown 101
qm set 101 --memory 10240
qm start 101
```

Update this guide and the ops-log entry to reflect the new resource allocation.

---

## Rollback

If Proxmox installation fails or the VM setup is unworkable:

1. Reinstall Ubuntu 22.04 on the NUC (same IP `10.0.10.20`)
2. Install Docker
3. Mount TrueNAS NFS shares
4. Restore from `archive/docker-backups/pre-proxmox-YYYYMMDD/`
5. `docker compose up -d`

TrueNAS and the k3s cluster are completely unaffected throughout — they never touched.
