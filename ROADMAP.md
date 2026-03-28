# Roadmap

This is a living document. It reflects current priorities, the reasoning behind them, and where this infrastructure is heading. Items move through **Now → Next → Later → Someday** as the project evolves.

For completed work, see [CHANGELOG.md](CHANGELOG.md). For detailed records of significant changes, see [docs/ops-log/](docs/ops-log/).

---

## Now
*Active — currently in flight.*

### Cluster Rebuild — Fresh Production Cluster
**Why now:** Decommissioning Proxmox and the staging cluster. Rebuilding the prod k3s cluster from scratch with the new architecture: single `main` branch, PR-based validation, no staging environment.
**Depends on:** Docker bare metal restore complete ✓
**Linked:** [ADR-012](docs/adr/ADR-012-pr-validation-pipeline.md)

### Cloudflare Tunnel
**Why now:** Currently relying on DNS proxying which requires open ports on the router. Cloudflare Tunnel eliminates all inbound port exposure with zero performance trade-off.
**Depends on:** Pi-hole (split DNS needed before tunnel is useful internally)
**Linked:** [Guide 05](docs/guides/05-Networking-MetalLB-Traefik.md)

### Pi-hole (Split DNS + Ad Blocking)
**Why now:** Required for the split DNS model — internal services resolve `*.kagiso.me → 10.0.10.110` on LAN without being publicly exposed. Doubles as network-wide ad blocking.
**Depends on:** Nothing (runs on RPi, already provisioned)
**Linked:** [networking.md](docs/architecture/networking.md)

### Wildcard TLS Certificate (DNS-01)
**Why now:** Internal services accessed via LAN or Tailscale should have valid browser-trusted certs. DNS-01 via Cloudflare API issues a `*.kagiso.me` wildcard with no port exposure — cleaner than any alternative.
**Depends on:** Cloudflare API token, cert-manager already deployed

---

## Next
*Committed — clear enough to start, queued behind Now.*

### Gatus on bran (Uptime Monitoring)
**Why:** Out-of-band uptime monitoring that survives k3s outages. Gatus runs on bran as a lightweight Go binary (~20MB RAM), config-driven via YAML (lives in this repo). Monitors public services end-to-end via Cloudflare tunnel URLs, internal services via `*.kagiso.me`, and k3s nodes directly. Exposed at `status.kagiso.me` via cloudflared.
**Depends on:** Cloudflare Tunnel (for `status.kagiso.me` exposure)

### Tailscale + Headscale Setup
**Why:** Private remote access for Plex, SSH, and kubectl — services that should never touch Cloudflare. Headscale runs on bran as the self-hosted coordination server, exposed via cloudflared. Tailscale first to validate the workflow, Headscale replaces the hosted coordination server.
**Note:** Headscale runs on bran alongside Pi-hole and cloudflared.

### Beesly (Personal AI Assistant)
**Why:** Voice interface for the homelab — talk to Beesly to query cluster status, manage containers, check NAS health, run Ansible playbooks, and more. Proactive alerts when pods crash, disks fill, or services go down.
**Linked:** [projects/DEV-beesly/](projects/DEV-beesly/)

### Cloudflare Zero Trust
**Why:** Adds identity-based access (Google/GitHub OAuth) in front of any Cloudflare Tunnel service with no code changes. A 2-minute configuration per service that significantly raises the security bar for publicly exposed UIs.
**Depends on:** Cloudflare Tunnel deployed

### Personal Website (kagiso.me)
**Why:** A live window into the homelab — not a static portfolio. Features a live changelog (from `CHANGELOG.md`), roadmap (from `ROADMAP.md`), real-time service status (Gatus), and adapted guides for a public audience.
**Stack:** Astro, custom dark theme, GitHub Pages
**Linked:** Separate repo — `kagiso-me/website`

---

## Later
*Planned — direction is clear, not yet scheduled.*

### Media Conversion Enforcement App
**Why:** Ensure all media in the Plex library is in a direct-play compatible format (H.264 + AAC). `ffprobe` scans the library, flags files requiring transcoding, queues them for `ffmpeg` conversion automatically. Eliminates transcoding overhead on the NUC.

### Add Spare ThinkCentre as 4th k3s Worker
**Why:** Additional compute and memory headroom in the prod cluster for running more application workloads without resource pressure. Simple `ansible-playbook` addition — no cluster disruption.
**Depends on:** Need the capacity (deploy applications first, add worker when felt)

### Grafana Dashboards
**Why:** Currently running default dashboards. Custom dashboards for TrueNAS pool health, ZFS scrub status, Plex sessions, Sonarr/Radarr queue, and backup success/failure would give a real operations view of the entire homelab at a glance.

### NUC RAM Upgrade (8GB → 16GB)
**Why:** The Intel NUC i3-7100U is running Docker bare metal with 8GB. 16GB would give comfortable headroom as the media stack grows. ~$30–40 for a SO-DIMM DDR4 kit.

---

## Someday
*Ideas worth keeping. No timeline, no commitment.*

### Pulse (Uptime & Incident Monitoring Platform)
**Why:** Build a monitoring platform that improves on Uptime Kuma and Gatus in every dimension — GitOps-native YAML config, real-time WebSocket dashboard, dependency graph with root-cause alert suppression, SLA burn rate tracking, historical reports. Single Go binary, runs on bran as an out-of-band monitor.
**Linked:** [projects/pulse/](projects/pulse/README.md)

### RPi 4 Upgrade
The RPi 3B+ (armv7l) can't run arm64-only tooling. A RPi 4 (4GB+, aarch64) would make the control hub significantly more capable.

### Gatus on Contabo (External Vantage Point)
Independent external uptime monitoring from a vantage point completely separate from the homelab. If the entire homelab or Cloudflare Tunnel goes down, this still fires.

### Wiki (Outline or Gitea)
Self-hosted wiki at `wiki.homelab` (internal DNS). All alert runbook URLs in Prometheus already point here — they resolve automatically once the wiki is running.

### Home Assistant
Smart home integration. Low priority until other fundamentals are solid.

---

## Recently Shipped
*Last 30 days. Full details in [docs/ops-log/](docs/ops-log/).*

| Date | What | Detail |
|------|------|--------|
| 2026-03-28 | Architecture pivot — decommission Proxmox + staging, bare metal Docker at 10.0.10.20 | [ADR-006 superseded](docs/adr/ADR-006-proxmox-pivot.md) |
| 2026-03-28 | New CI/CD model — PR-based validation with flux diff, no staging cluster | [ADR-012](docs/adr/ADR-012-pr-validation-pipeline.md) |
| 2026-03-28 | Renovate Bot — automated dependency update PRs | [renovate.json](renovate.json) |
| 2026-03-22 | GitOps promotion pipeline — main → staging → prod automation | Superseded by ADR-012 |
| 2026-03-16 | Initial infrastructure — 3-node k3s, FluxCD v2, SOPS/age, Prometheus + Grafana + Loki | [ops-log](docs/ops-log/2026-03-16-initial-infrastructure-setup.md) |
| 2026-03-16 | Platform stack — MetalLB + cert-manager + Traefik v3 | [ops-log](docs/ops-log/2026-03-16-deploy-platform-stack.md) |
