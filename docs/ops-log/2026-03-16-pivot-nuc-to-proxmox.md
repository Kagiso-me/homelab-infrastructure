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
NUC (Proxmox VE) — 10.0.10.30
├── ubuntu-2204-cloud (VM 9000) — template, never runs
├── docker-vm       — 10.0.10.32 (2 vCPU, 8GB RAM, 80GB)
│   └── Docker Compose
│       └── Sonarr, Radarr, Plex (+ arr stack)
└── staging-k3s     — 10.0.10.31 (2 vCPU, 6GB RAM, 60GB)
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
   - IP: `10.0.10.30` (new dedicated Proxmox host IP)
   - Gateway: `10.0.10.1`
   - DNS: `10.0.10.1`
4. First login — Proxmox web UI at `https://10.0.10.30:8006`

### Post-Install Host Config

```bash
ssh root@10.0.10.30

# Switch to community (no-subscription) repo
echo "deb http://download.proxmox.com/debian/pve bookworm pve-no-subscription" \
  > /etc/apt/sources.list.d/pve-community.list
sed -i 's/^deb/#deb/' /etc/apt/sources.list.d/pve-enterprise.list
apt update && apt dist-upgrade -y

# Install useful tools
apt install -y vim htop iotop ncdu curl wget

# Add SSH key (replace with your actual public key)
mkdir -p ~/.ssh
echo "ssh-rsa AAAA..." >> ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys

# Disable the enterprise subscription nag popup in the web UI
sed -i.bak "s/res === null/false/" /usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js
systemctl restart pveproxy
```

### Automated VM Backups (vzdump)

Backups are stored on a TrueNAS NFS share, not local NVMe.

**TrueNAS NFS share setup:**
- Dataset owned by `kagiso` — set **Mapall User: kagiso** on the NFS share
- Enable **NFSv3** (System Settings → Services → NFS → Configure) — required for Proxmox to enumerate exports via `showmount`
- Add Proxmox host IP to Authorized Hosts on the share

**Add NFS storage in Proxmox:**
- Datacenter → Storage → Add → NFS
- Server: TrueNAS IP, export path, Content: `VZDump backup file`

**Backup job:**
- Datacenter → Backup → Add
- Schedule: Sunday 02:00, all VMs, storage: `truenas-backup`, mode: snapshot, compress: zstd
- This gives weekly rollback points before any risky change

---

## Step 3 — Create Cloud-Init Template

VMs are provisioned from a cloud-init template rather than the Ubuntu installer.
This makes new VMs take ~30 seconds instead of 10+ minutes and eliminates manual
installer interaction.

```bash
ssh root@10.0.10.30

# Download Ubuntu 22.04 cloud image (no GUI, cloud-ready, ~600MB)
wget https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img

# Create base VM — ID 9000 is the template convention
qm create 9000 \
  --name ubuntu-2204-cloud \
  --memory 2048 \
  --cores 2 \
  --cpu host \
  --net0 virtio,bridge=vmbr0 \
  --ostype l26 \
  --agent enabled=1 \
  --serial0 socket \
  --vga serial0

# Import the cloud image as the disk
qm importdisk 9000 jammy-server-cloudimg-amd64.img local-lvm

# Attach disk, add cloud-init drive, set boot order
qm set 9000 \
  --scsi0 local-lvm:vm-9000-disk-0,discard=on,ssd=1 \
  --ide2 local-lvm:cloudinit \
  --boot order=scsi0 \
  --scsihw virtio-scsi-pci

# Set cloud-init defaults — SSH key is injected at clone time
qm set 9000 \
  --ciuser kagiso \
  --sshkeys ~/.ssh/authorized_keys \
  --ipconfig0 ip=dhcp

# Convert to template (one-way — clones inherit all settings)
qm template 9000

# Clean up the downloaded image
rm jammy-server-cloudimg-amd64.img
```

> **Note:** Template VM 9000 never runs. It is only cloned.

---

## Step 4 — Create docker-vm

```bash
ssh root@10.0.10.30

# Clone template and configure
qm clone 9000 3032 --name docked --full
qm set 100 \
  --memory 8192 \
  --cores 2 \
  --cpu host \
  --ipconfig0 ip=10.0.10.32/24,gw=10.0.10.1 \
  --nameserver 10.0.10.10

# Expand disk to 80GB before first boot
qm resize 3032 scsi0 80G

qm start 3032
```

Cloud-init configures hostname, injects SSH key, sets static IP, and expands the
root filesystem — all on first boot. No installer interaction needed.

### First Boot — docker-vm

```bash
# SSH available immediately after boot (key injected by cloud-init)
ssh kagiso@10.0.10.32

# Install QEMU guest agent — enables graceful shutdown and IP visibility in Proxmox UI
sudo apt install -y qemu-guest-agent
sudo systemctl enable --now qemu-guest-agent

# Install Docker
curl -fsSL https://get.docker.com | sudo bash
sudo usermod -aG docker kagiso
```

---

## Step 5 — Restore Docker Stack

```bash
ssh kagiso@10.0.10.32

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

## Step 6 — Create staging-k3s VM

```bash
ssh root@10.0.10.30

# Clone template and configure
qm clone 9000 3031 --name staging-k3s --full
qm set 101 \
  --memory 4096 \
  --cores 2 \
  --cpu host \
  --ipconfig0 ip=10.0.10.31/24,gw=10.0.10.1 \
  --nameserver 10.0.10.10

# Expand disk to 60GB before first boot
qm resize 3031 scsi0 60G

qm start 3031
```

### First Boot — staging-k3s

```bash
ssh kagiso@10.0.10.31

# Install QEMU guest agent
sudo apt install -y qemu-guest-agent
sudo systemctl enable --now qemu-guest-agent

# Install k3s (single-node)
curl -sfL https://get.k3s.io | sh -s - \
  --disable traefik \
  --write-kubeconfig-mode 644

kubectl get nodes
```

---

## Step 7 — Bootstrap Flux on Staging

From the RPi (`ssh kagiso@10.0.10.10`):

```bash
# Copy and fix kubeconfig
scp kagiso@10.0.10.31:/etc/rancher/k3s/k3s.yaml ~/.kube/staging-config
sed -i 's/127.0.0.1/10.0.10.31/' ~/.kube/staging-config
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

## Step 8 — Enable Staging Promotion Gate

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

- Proxmox host node exporter: `10.0.10.30:9100`
- docker-vm node exporter: `10.0.10.32:9100`
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
