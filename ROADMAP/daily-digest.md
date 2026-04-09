# Daily Digest Overhaul

**Target:** Early–Mid June 2026  
**Plan file:** `~/.claude/plans/magical-foraging-leaf.md`

## Problem

The current digest sends a point-in-time CPU/memory snapshot at 08:00 — not meaningful as a daily summary. Also references decommissioned nodes (proxmox, docker-vm, truenas jobs).

## Scope

**Phase 1 — Mikrotik syslog → Loki**
- Add Promtail syslog receiver (UDP 1514) to in-cluster loki-stack
- Expose via Kubernetes Service
- Configure Mikrotik to forward firewall/system logs via syslog

**Phase 2 — Rewrite digest script**

Replace CPU/memory snapshot with 6 actionable sections:

1. Firing alerts (skip Watchdog/InfoInhibitor) — Prometheus
2. Disk usage / (warn >85%) — Prometheus
3. Top pod restarts over 24h — Prometheus
4. Backup status + last success date — Prometheus
5. Flux sync health (kustomizations not Ready) — Prometheus
6. Mikrotik unauthorised login attempts 24h — Loki

## Files

- `platform/observability/daily-digest/configmap-script.yaml` — full rewrite
- `platform/observability/loki/helmrelease.yaml` — add promtail syslog scrape config
- `platform/observability/loki/syslog-service.yaml` — new UDP Service
- `platform/observability/loki/kustomization.yaml` — add syslog-service.yaml
