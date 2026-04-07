# ADR-013 — Public Site Live Data Pipeline

**Status:** Accepted
**Date:** 2026-04-06
**Deciders:** Platform team

---

## Context

`kagiso-me.github.io` is a public-facing Astro static site that displays live homelab status —
running services, cluster node health, Flux sync state, and backup recency. Static sites cannot
query internal infrastructure directly (no access to RFC-1918 addresses from a browser).

The challenge: how do you get live internal data onto a public static site without exposing
internal infrastructure to the internet?

## Decision

**A GitHub Actions workflow runs on a schedule, SSHes into varys, collects live data, and
commits the result as a static JSON file (`public/data/live.json`) into the site repo.**

The site reads this file at page load — it is a static asset, not a live API call.

### Pipeline flow

```
[Schedule: every 30min]
       │
       ▼
GitHub Actions (self-hosted runner on varys)
       │  SSH into varys
       ▼
fetch-live-data.sh
  ├── kubectl get nodes / pods / kustomizations
  ├── Prometheus queries (CPU, memory, uptime)
  ├── Sonarr API  → series count
  ├── Radarr API  → movie count
  ├── SABnzbd API → queue state + size remaining
  ├── Plex API    → active stream count
  └── Uptime Kuma → service heartbeat statuses
       │
       ▼
live.json committed to Kagiso-me/Kagiso-me.github.io
       │
       ▼
Astro build triggers → GitHub Pages deploy
       │
       ▼
Public site reads /data/live.json (static, cached at CDN)
```

### Why 30-minute schedule

5-minute polling was considered but rejected — it generates excessive Actions runs, SSH
connections, and API calls for a personal status page where staleness of 30 minutes is
perfectly acceptable.

### Service endpoints

All internal service calls use IP addresses. Internal DNS is not yet configured on the
UniFi USG (Network 7.2.97 does not expose DNS record management in the UI).

**When internal DNS is available**, update the endpoint block at the top of
`kagiso-me.github.io/scripts/fetch-live-data.sh` — all IPs are centralised there with a
`TODO` comment marking the migration point. No other files need changing.

Current IP → intended DNS mapping:

| Service | Current | Intended |
|---------|---------|----------|
| Sonarr | `10.0.10.20:8989` | `sonarr.home` |
| Radarr | `10.0.10.20:7878` | `radarr.home` |
| SABnzbd | `10.0.10.20:8085` | `sabnzbd.home` |
| Plex | `10.0.10.20:32400` | `plex.home` |
| Uptime Kuma | `10.0.10.20:3001` | `uptime.home` |

### Uptime Kuma placement

Uptime Kuma runs on the Docker host (`10.0.10.20`). Moving it to k3s was considered but
rejected — it only needs to be reachable from varys (internal), not from the public internet.
Running it on Docker is simpler and sufficient for its purpose as a service health monitor
and heartbeat API source.

### Plex token

Stream count requires a Plex authentication token. This is stored as the `PLEX_TOKEN`
environment variable on varys (`~/.bashrc`). Without it, the script falls back to a simple
HTTP health check (status only, no stream count).

### Runner placement

The `Kagiso-me.github.io` runner lives in `~/actions-runner-site/` on varys — separate from
the `homelab-infrastructure` runner in `~/actions-runner/`. See ADR-007 for the multi-runner
directory convention.

**Planned migration:** when hodor (10.0.10.9, RPi) is provisioned, the site runner will
move there. hodor's sole purpose is observability queries — kubectl reads, Prometheus scrapes,
service API calls. This separates the observer from the control plane (varys).

## Consequences

**Positive:**
- No internal infrastructure is exposed to the internet
- The public site works even if the homelab is down (shows last known state with timestamp)
- Data collection is decoupled from the site build — they run on independent schedules
- Adding a new service to the ticker requires one entry in `fetch-live-data.sh` and `index.astro`

**Negative:**
- Data is stale by up to 30 minutes
- If varys is offline, the workflow queues indefinitely (same as the homelab-infrastructure runner)
- Plex stream counts require a manually-obtained token that must be refreshed if it expires

## Required secrets

| Secret | Repository | Purpose |
|--------|------------|---------|
| `SITE_DEPLOY_TOKEN` | `Kagiso-me.github.io` | Fine-grained PAT to commit `live.json` back to the repo. Scoped to `Contents: read+write` on `Kagiso-me.github.io` only. |
| `SSH_PRIVATE_KEY` | `Kagiso-me.github.io` | SSH key for the workflow to connect to varys and run `fetch-live-data.sh` |
