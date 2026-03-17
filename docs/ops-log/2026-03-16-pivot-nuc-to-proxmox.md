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

## Before → After

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
│       └── Sonarr, Radarr, Plex (+ arr stack)
└── staging-k3s     — 10.0.10.22 (2 vCPU, 6GB RAM, 60GB)
    └── k3s single-node
        └── Flux → clusters/staging/ → apps/staging/
```

Monitoring stack is **decommissioned from Docker** — kube-prometheus-stack on k3s
scrapes all external targets via `additionalScrapeConfigs`. Frees ~2GB RAM on `docker-vm`.

NFS mounts from TrueNAS are identical — `docker-vm` mounts `tera/media` the same way.
No data migration required.

### VM Resource Allocation

| | Proxmox host | docker-vm | staging-k3s | Total |
|---|---|---|---|---|
| **RAM (16GB now)** | ~2GB | 8GB | 6GB | 16GB |
| **RAM (32GB after upgrade)** | ~2GB | 12GB | 10GB | ~24GB |
| **vCPU** | — | 2 | 2 | 4 threads |
| **Disk** | ~40GB | 80GB | 60GB | ~180GB |

> **Interim resource note:** Migration proceeding with 16GB RAM. RAM upgrade to 32GB
> expected ~2026-03-23, at which point docker-vm → 12GB and staging-k3s → 10GB.

A spare ThinkCentre M93p is retained as a cold spare / future 4th k3s worker.

---

## Pre-Migration Checklist

Before touching the NUC:

- [ ] Extend kube-prometheus-stack with `additionalScrapeConfigs` for TrueNAS, NUC, RPi
- [ ] Add PrometheusRule resources for infrastructure + TrueNAS alert rules in k3s
- [ ] Verify all external targets healthy in k3s Prometheus before proceeding
- [ ] TrueNAS `archive/docker-backups` dataset accessible and has free space
- [ ] Docker compose files committed in this repo (under `docker/`)
- [ ] Note any volumes with state that aren't in TrueNAS (Grafana dashboards, Prometheus data)
- [ ] Proxmox VE ISO downloaded and flashed to USB (8GB+)
- [ ] SSH access to RPi (`10.0.10.10`) confirmed — control hub during outage

---

## Step 1 — Backup Docker Host

From the NUC (`ssh kagiso@10.0.10.20`):

```bash
# Mount the TrueNAS backup share
sudo mkdir -p /mnt/archive
sudo mount -t nfs 10.0.10.80:/mnt/archive /mnt/archive

# Create a timestamped backup directory
BACKUP_DIR="/mnt/archive/docker-backups/pre-proxmox-$(date +%Y%m%d)"
sudo mkdir -p "$BACKUP_DIR"

# Backup compose files and configs
sudo tar czf "$BACKUP_DIR/docker-compose-backup.tar.gz" \
  ~/docker/ \
  /etc/docker/ \
  2>/dev/null

# Export named volumes (includes Grafana dashboards, Prometheus TSDB, app state)
sudo tar czf "$BACKUP_DIR/docker-volumes.tar.gz" /var/lib/docker/volumes/

# Verify
ls -lah "$BACKUP_DIR"
```

---

## Step 2 — Install Proxmox VE

1. Flash Proxmox VE ISO to USB (Rufus on Windows or `dd` on Linux)
2. Boot NUC from USB — press **F10** at boot for boot menu
3. Installer settings:
   - Target disk: 256GB NVMe
   - Hostname: `nuc.homelab`
   - IP: `10.0.10.20` (same as before — keeps DNS/NFS exports working)
   - Gateway: `10.0.10.1`
   - DNS: `10.0.10.1`
4. First login — Proxmox web UI at `https://10.0.10.20:8006`
5. Disable enterprise repo (no subscription):

```bash
ssh root@10.0.10.20

echo "deb http://download.proxmox.com/debian/pve bookworm pve-no-subscription" \
  > /etc/apt/sources.list.d/pve-community.list
sed -i 's/^deb/#deb/' /etc/apt/sources.list.d/pve-enterprise.list
apt update && apt dist-upgrade -y
```

---

## Step 3 — Create docker-vm

```bash
# From Proxmox host (after uploading Ubuntu 22.04 ISO to Proxmox storage)
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

During Ubuntu install: hostname `docker-vm`, IP `10.0.10.21` (static), user `kagiso`, enable SSH.

```bash
# After install — install Docker
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
echo "10.0.10.80:/mnt/tera/media    /mnt/media     nfs  defaults,_netdev  0 0" | sudo tee -a /etc/fstab
echo "10.0.10.80:/mnt/tera          /mnt/downloads  nfs  defaults,_netdev  0 0" | sudo tee -a /etc/fstab
echo "10.0.10.80:/mnt/archive       /mnt/archive    nfs  defaults,_netdev  0 0" | sudo tee -a /etc/fstab
sudo mount -a

# Restore compose files and volumes from backup
BACKUP_DIR="/mnt/archive/docker-backups/pre-proxmox-$(date +%Y%m%d)"
sudo tar xzf "$BACKUP_DIR/docker-compose-backup.tar.gz" -C /
sudo tar xzf "$BACKUP_DIR/docker-volumes.tar.gz" -C /

# Start services
cd ~/docker && docker compose up -d

# Verify
docker ps
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

During Ubuntu install: hostname `staging`, IP `10.0.10.22` (static), user `kagiso`, enable SSH.

```bash
# Install k3s (single-node)
ssh kagiso@10.0.10.22
curl -sfL https://get.k3s.io | sh -s - \
  --disable traefik \
  --write-kubeconfig-mode 644

kubectl get nodes
```

---

## Step 6 — Bootstrap Flux on Staging

From the RPi (`ssh kagiso@10.0.10.10`):

```bash
# Copy and fix kubeconfig
scp kagiso@10.0.10.22:/etc/rancher/k3s/k3s.yaml ~/.kube/staging-config
sed -i 's/127.0.0.1/10.0.10.22/' ~/.kube/staging-config
export KUBECONFIG=~/.kube/staging-config

# Bootstrap Flux against the staging path
flux bootstrap github \
  --owner=Kagiso-me \
  --repository=homelab-infrastructure \
  --branch=main \
  --path=clusters/staging \
  --personal

# Verify
flux get kustomizations
flux get helmreleases -A
```

---

## Step 7 — Enable Staging Promotion Gate

Once staging is healthy, add the `STAGING_KUBECONFIG` GitHub Actions secret:

```bash
# From RPi — encode staging kubeconfig
cat ~/.kube/staging-config | base64 | tr -d '\n'
```

Add as a GitHub Actions secret named `STAGING_KUBECONFIG`, then uncomment the
`staging-health` job in [`.github/workflows/promote-to-prod.yml`](../../.github/workflows/promote-to-prod.yml).

---

## Post-Migration — Consolidate Monitoring

Extend kube-prometheus-stack to scrape all external targets, then decommission the
Docker monitoring stack:

- Proxmox host node exporter: `10.0.10.20:9100`
- docker-vm node exporter: `10.0.10.21:9100`
- TrueNAS SNMP / node exporter: `10.0.10.80`
- RPi node exporter: `10.0.10.10:9100`

---

## Post-RAM Upgrade — Expand VM Resources (~2026-03-23)

```bash
qm shutdown 100 && qm set 100 --memory 12288 && qm start 100
qm shutdown 101 && qm set 101 --memory 10240 && qm start 101
```

---

## Rollback

If Proxmox install fails:

1. Reinstall Ubuntu 22.04 on the NUC (same IP `10.0.10.20`)
2. Install Docker, mount TrueNAS NFS shares
3. Restore from `archive/docker-backups/pre-proxmox-YYYYMMDD/`
4. `docker compose up -d`

TrueNAS and the k3s cluster are completely unaffected throughout.

---

## Related

- ADR: `docs/architecture/decisions/ADR-006-proxmox-pivot.md`
- Staging cluster config: `clusters/staging/`
- Promotion pipeline: `.github/workflows/promote-to-prod.yml`
