# Roadmap

This is a living document. It reflects current priorities, the reasoning behind them, and where this infrastructure is heading. Items move through **Now → Next → Later → Someday** as the project evolves.

For completed work, see [CHANGELOG.md](CHANGELOG.md). For detailed records of significant changes, see [docs/ops-log/](docs/ops-log/).

---

## Now
*Active — currently in flight.*

### Proxmox Migration
**Why now:** The Intel NUC running bare Docker is a single point of failure with no isolation between services. Converting to Proxmox gives a proper hypervisor with a `docker-vm` for media services and a `staging-k3s` VM for the GitOps promotion pipeline — both things needed before deploying real applications.
**Depends on:** None (proceeding with 16GB, RAM upgrade to follow)
**Linked:** [ADR-006](docs/architecture/decisions/ADR-006-proxmox-pivot.md) · [ops-log](docs/ops-log/2026-03-16-pivot-nuc-to-proxmox.md)

### Cloudflare Tunnel
**Why now:** Currently relying on DNS proxying which requires open ports on the router. Cloudflare Tunnel eliminates all inbound port exposure with zero performance trade-off.
**Depends on:** Pi-hole (split DNS needed before tunnel is useful internally)
**Linked:** [Guide 03](docs/guides/03-Networking-Platform.md)

### Pi-hole (Split DNS + Ad Blocking)
**Why now:** Required for the split DNS model — internal services resolve `*.kagiso.me → 10.0.10.110` on LAN without being publicly exposed. Doubles as network-wide ad blocking.
**Depends on:** Nothing (runs on RPi, already provisioned)
**Linked:** [networking.md](docs/architecture/networking.md)

### Wildcard TLS Certificate (DNS-01)
**Why now:** Internal services accessed via LAN or Tailscale should have valid browser-trusted certs. DNS-01 via Cloudflare API issues a `*.kagiso.me` wildcard with no port exposure — cleaner than any alternative.
**Depends on:** Cloudflare API token, cert-manager already deployed

### Consolidate Monitoring to k3s
**Why now:** Docker host currently runs a redundant Prometheus + Grafana + Loki + Alertmanager stack alongside the kube-prometheus-stack in k3s. When docker-vm is provisioned, the Docker monitoring stack does not get restored. k3s Prometheus takes over scraping all external targets (TrueNAS, docker-vm, RPi) via `additionalScrapeConfigs`.
**Depends on:** Proxmox migration (natural cutover point)

---

## Next
*Committed — clear enough to start, queued behind Now.*

### Tailscale Setup
**Why:** Private remote access for Plex, SSH, and kubectl — services that should never touch Cloudflare. Tailscale handles its own certificate infrastructure and gives seamless access from any device.
**Note:** Headscale (self-hosted coordination server) is the long-term direction — Tailscale first to validate the workflow.

### NUC RAM Upgrade (16GB → 32GB)
**Why:** With 16GB the Proxmox allocation is tight (Proxmox 2GB + docker-vm 6GB + staging-k3s 8GB = 0 headroom). 32GB unlocks 14GB for additional LXC containers and future VMs. ~$50 for a SO-DIMM DDR4 kit.
**Impact:** After upgrade — docker-vm gets 8GB, staging-k3s gets 8GB, 14GB free for LXC workloads.

### Flux Bootstrap — Staging Cluster
**Why:** The `clusters/staging/` path and GitOps promotion pipeline (main → staging → prod) are ready. The staging cluster itself needs bootstrapping once the staging-k3s VM is provisioned.
**Depends on:** Proxmox migration (staging-k3s VM provisioned)
**Linked:** [Guide 04](docs/guides/04-Flux-GitOps.md)

### Cloudflare Zero Trust
**Why:** Adds identity-based access (Google/GitHub OAuth) in front of any Cloudflare Tunnel service with no code changes. A 2-minute configuration per service that significantly raises the security bar for publicly exposed UIs.
**Depends on:** Cloudflare Tunnel deployed

---

## Later
*Planned — direction is clear, not yet scheduled.*

### Nextcloud
**Why:** Self-hosted file sync and collaboration. Replaces reliance on commercial cloud storage for personal documents and shared files. Will run in k3s, exposed via Cloudflare Tunnel, large syncs via Tailscale.

### Immich
**Why:** Self-hosted photo and video library (Google Photos replacement). Media stored on TrueNAS `archive`. Day-to-day access via Cloudflare Tunnel, initial bulk library import via Tailscale to avoid ToS complications.

### Media Conversion Enforcement App
**Why:** Ensure all media in the Plex/Jellyfin library is in a direct-play compatible format (H.264 + AAC). `ffprobe` scans the library, flags files requiring transcoding, queues them for `ffmpeg` conversion automatically. Eliminates any transcoding overhead on the NUC.
**Linked:** [Reminder set for 2026-03-23](docs/ops-log/)

### Add Spare ThinkCentre as 4th k3s Worker
**Why:** Additional compute and memory headroom in the prod cluster for running more application workloads without resource pressure. Simple `ansible-playbook` addition — no cluster disruption.
**Depends on:** Need the capacity (deploy applications first, add worker when felt)

### Grafana Dashboards
**Why:** Currently running default dashboards. Custom dashboards for TrueNAS pool health, ZFS scrub status, Plex sessions, Sonarr/Radarr queue, and backup success/failure would give a real operations view of the entire homelab at a glance.

---

## Someday
*Ideas worth keeping. No timeline, no commitment.*

### Headscale (Self-hosted Tailscale Coordination Server)
Replace reliance on Tailscale's hosted coordination server with Headscale running on the RPi or as an LXC on Proxmox. Full control, no external dependency for VPN coordination.

### RPi 4 Upgrade
The RPi 3B+ (armv7l) can't run Claude Code or any arm64-only tooling. A RPi 4 (4GB+, aarch64) would make the control hub significantly more capable — running Claude Code directly on the node for natural language infrastructure operations.

### Uptime Kuma on Contabo
Independent external uptime monitoring from a vantage point completely separate from the homelab. If the entire homelab (or Cloudflare Tunnel) goes down, monitoring still fires from Contabo.

### Wiki (Outline or Gitea)
Self-hosted wiki at `wiki.homelab` (internal DNS). All alert runbook URLs in Prometheus already point here — they resolve automatically once the wiki is running. Runbook files in `docs/operations/runbooks/alerts/` serve as the source content.

### Home Assistant
Smart home integration as an LXC on Proxmox once the 32GB RAM upgrade is in place and headroom exists. Low priority until other fundamentals are solid.

### Additional LXC Workloads on Proxmox
With 32GB RAM, ~14GB of headroom exists beyond docker-vm and staging-k3s. Potential LXCs: dedicated Headscale server, Vaultwarden (self-hosted Bitwarden), additional monitoring nodes.

---

## Recently Shipped
*Last 30 days. Full details in [docs/ops-log/](docs/ops-log/).*

| Date | What | Detail |
|------|------|--------|
| 2026-03-16 | Initial infrastructure — 3-node k3s, FluxCD v2, SOPS/age, Prometheus + Grafana + Loki | [ops-log](docs/ops-log/2026-03-16-initial-infrastructure-setup.md) |
| 2026-03-16 | Platform stack — MetalLB + cert-manager + Traefik v3 | [ops-log](docs/ops-log/2026-03-16-deploy-platform-stack.md) |
| 2026-03-16 | Architecture pivot — Intel NUC to Proxmox hypervisor | [ops-log](docs/ops-log/2026-03-16-pivot-nuc-to-proxmox.md) · [ADR-006](docs/architecture/decisions/ADR-006-proxmox-pivot.md) |
| 2026-03-16 | GitOps promotion pipeline — main → staging → prod automation | [Guide 04](docs/guides/04-Flux-GitOps.md) |
| 2026-03-16 | Ops-log system and CHANGELOG automation | [ops-log README](docs/ops-log/README.md) |
