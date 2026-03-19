# Pulse — Uptime & Incident Monitoring

> **Status:** Planning — 2026-03-17
> **Inspired by:** Uptime Kuma, Gatus — but better in every way

Pulse is a self-hosted uptime and incident monitoring platform. GitOps-native config, real-time dashboard, dependency-aware alerting, and deep analytics. Built to replace both Uptime Kuma and Gatus.

---

## What's wrong with existing tools

| | Uptime Kuma | Gatus |
|---|---|---|
| Config | SQLite (not GitOps) | YAML ✓ |
| Real-time UI | ✓ | ✗ (polling) |
| Dependency graph | ✗ | ✗ |
| Smart alert routing | ✗ | ✗ |
| Historical SLA reports | basic | ✗ |
| Screenshot on failure | ✗ | ✗ |
| Response body diffing | ✗ | ✗ |
| Kubernetes CRD native | ✗ | ✗ |
| API with scoped keys | ✗ | ✗ |
| Incident replay | ✗ | ✗ |

Pulse addresses all of them.

---

## Architecture

```
config/ (YAML — hot-reloaded, lives in git)
    │
    ▼
pulse-server  (Go binary)
    ├── Check engine       — HTTP, TCP, DNS, gRPC, multi-step, PromQL threshold
    ├── Dependency engine  — graph eval, alert suppression, root-cause routing
    ├── Incident manager   — dedup, flap dampening, escalation, acknowledgement
    ├── History store      — SQLite (default) / PostgreSQL
    ├── WebSocket hub      — real-time dashboard push
    ├── REST API           — scoped API keys, OpenAPI docs
    └── Notifier           — Slack, Teams, Discord, PagerDuty, webhook, email, Beesly

pulse-frontend  (React)
    ├── Live dashboard     — WebSocket, real-time status
    ├── Dependency graph   — interactive, draggable
    ├── Incident timeline  — with replay scrubber
    ├── Analytics          — SLA burn rate, MTTR, heatmaps, percentile response times
    └── Public status page — embeddable widget, subscriber notifications
```

**Tech stack:**
- **Backend:** Go — single binary, low memory, fast startup, runs on bran or docker-vm
- **Frontend:** React + a modern design system (TBD — leaning toward Radix UI + Tailwind)
- **Storage:** SQLite by default, PostgreSQL for larger installs
- **Realtime:** WebSocket
- **Config:** YAML, file-watched with hot-reload

---

## Check Types

| Type | Notes |
|------|-------|
| HTTP/S | Status code, response body, TLS cert expiry |
| TCP | Port open/close |
| DNS | Resolution, expected record |
| ICMP ping | Latency + packet loss |
| gRPC | Health protocol |
| Multi-step | Simulate user flows (login → assert token → call protected endpoint) |
| Docker container | Health status via Docker API |
| Kubernetes pod/deploy | Native k8s health check |
| Prometheus metric | Alert when a PromQL query exceeds a threshold |
| Certificate expiry | Forecast timeline, not just binary warning |
| Domain expiry | WHOIS-based, expiry countdown |
| Response body diff | Alert when page content changes unexpectedly |
| Custom script | Shell command, exit code determines status |

---

## Dependency Graph

The most important feature missing from both Uptime Kuma and Gatus.

```yaml
# config/monitors.yaml
monitors:
  - name: postgresql
    type: tcp
    host: 10.0.10.32
    port: 5432

  - name: nextcloud
    type: http
    url: https://nextcloud.kagiso.me
    depends_on: [postgresql]   # suppress nextcloud alert if postgresql is the root cause

  - name: immich
    type: http
    url: https://immich.kagiso.me
    depends_on: [postgresql]
```

When `postgresql` goes down, one alert fires (root cause). Nextcloud and Immich alerts are suppressed with a note: "Suppressed — dependency postgresql is down."

The dashboard shows an interactive graph — colour-coded, draggable — that lights up failure paths in real time.

---

## Alert Routing

Severity-based routing so the right channel gets the right message:

```yaml
# config/alerts.yaml
routing:
  - severity: critical
    channels: [beesly, slack-ops]    # Phil calls you + Slack
  - severity: warning
    channels: [slack-ops]
  - severity: info
    channels: [slack-general]

escalation:
  unacknowledged_after: 10m
  escalate_to: [slack-oncall]
```

Each alert auto-attaches a runbook link if one is configured for that monitor.

---

## Analytics & Reporting

- **SLA burn rate** — real-time indicator of monthly uptime budget consumed
- **Custom timeframe reports** — any range (last 6 months, last quarter, last year, custom)
- **MTTR / MTTD** — per service, trended over time
- **Incident frequency heatmap** — GitHub-style calendar, instantly reveals patterns
- **P50 / P95 / P99 response times** — not just averages
- **Exportable reports** — PDF and CSV for any timeframe and service selection
- **Per-service SLA badges** — embeddable in GitHub READMEs

---

## Incident Management

- **Flap dampening** — require N consecutive failures before alerting
- **Acknowledgement** — mark an incident as seen; suppress further pages
- **Escalation** — auto-escalate if unacknowledged after configurable timeout
- **Post-mortem fields** — root cause, timeline, resolution, prevention steps
- **Incident Replay** — scrub back through time and see exactly what the dashboard looked like at any point during an incident. Essential for post-mortems.
- **Auto-resolution** — when service recovers, close incident and notify

---

## Smart Features

**Screenshot on failure**
For HTTP checks, capture a headless browser screenshot when a check fails. Stored in the incident — invaluable when a service returns 200 but renders an error page.

**Response body diffing**
Store a hash of the expected response body. Alert when it changes unexpectedly — catches silent failures that a status-code check misses entirely.

**Maintenance windows**
```yaml
maintenance:
  - name: weekly k3s drain
    schedule: "0 2 * * 0"   # every Sunday 02:00
    duration: 2h
    suppress: [k3s-api, traefik, all-k3s-services]
```
GitHub Action integration: automatically open a maintenance window on deploy, close it on completion.

**Business hours awareness**
Tag services as business-hours-only — alert severity and routing change outside defined hours.

---

## Public Status Page

- Custom domain, full white-label
- Component grouping (Storage / Compute / Networking / Services)
- Incident communication — post updates as an incident progresses
- Email + RSS subscriber notifications
- Historical incident log with post-mortem summaries
- **Embeddable widget** — JS snippet or iframe for embedding live status in any site
- SLA percentage display per component

---

## API

Full REST API with scoped API keys:

```
GET  /api/v1/monitors              # list all monitors + current status
GET  /api/v1/monitors/:id/history  # uptime history for timeframe
GET  /api/v1/incidents             # incident list + filters
POST /api/v1/incidents/:id/ack     # acknowledge an incident
POST /api/v1/maintenance           # open a maintenance window
GET  /api/v1/status                # public status summary (no key required)
```

Key scopes: `read`, `write`, `admin`. Rate-limited per key. OpenAPI docs at `/api/docs`.

---

## Integrations

| Channel | Notes |
|---------|-------|
| Slack | Rich blocks with incident context |
| Microsoft Teams | Adaptive cards |
| Discord | Embeds |
| PagerDuty | Native incident sync |
| OpsGenie | Oncall routing |
| Telegram | |
| Email | Rich HTML with incident timeline |
| Webhook | Generic — compatible with n8n, Zapier, Make |
| **Beesly** | First-class — critical alerts trigger Phil to call you |
| Prometheus | `/metrics` endpoint — Grafana can scrape Pulse directly |

---

## Developer Experience

**CLI**
```bash
pulse status                          # live status in terminal
pulse ack <incident-id>               # acknowledge an incident
pulse maint open "k3s upgrade" 2h    # open a maintenance window
pulse report --from 2025-09-01 --to 2026-03-01 --format pdf
```

**Kubernetes CRD**
```yaml
apiVersion: pulse.io/v1
kind: Monitor
metadata:
  name: nextcloud
spec:
  type: http
  url: https://nextcloud.kagiso.me
  interval: 30s
  dependsOn: [postgresql]
  severity: critical
```

Monitors defined as k8s resources, managed by a controller, living in the same GitOps repo as the services they monitor.

**Config hot-reload** — edit YAML, changes apply within seconds, no restart required.

---

## Deployment

Single Go binary + static frontend assets. Runs anywhere:

```bash
# Docker
docker run -v ./config:/config -p 8080:8080 pulse/pulse:latest

# Binary (runs on bran — armv7l compatible target)
./pulse --config ./config/

# Kubernetes
kubectl apply -f https://pulse.io/install/k8s/latest.yaml
```

---

## Homelab Integration

For this homelab specifically:
- Runs on **bran** (`10.0.10.10`) as the out-of-band monitor (survives k3s outages)
- Scrapes k3s services via `*.kagiso.me` and internal IPs
- Prometheus `/metrics` scraped by kube-prometheus-stack → Grafana dashboards
- Feeds alerts to Beesly — critical incidents trigger Phil to call
- Config lives in `projects/pulse/config/` — GitOps managed, Flux-reconciled

---

## Release Strategy

Pulse will be built iteratively, dogfooded on this homelab at each stage before any public release.

### Alpha (internal only)
Running on this homelab. Unstable, incomplete, no guarantees. Each iteration adds features and is validated against real infrastructure before progressing.

| Iteration | Focus |
|-----------|-------|
| α1 | Core check engine + SQLite + basic HTTP dashboard |
| α2 | WebSocket real-time + Slack/webhook notifications |
| α3 | Dependency graph (config + UI) |
| α4 | REST API + scoped API keys |
| α5 | Public status page + SLA reporting |
| α6 | Historical reports + analytics (MTTR, heatmaps, percentile response times) |
| α7 | Screenshot on failure + response body diffing |
| α8 | Incident replay + post-mortem fields |

### Beta (first public release — `v0.1.0-beta`)
The beta is the first release made available outside this homelab. It will be feature-complete for the v1 scope below, documented, and stable enough for others to self-host. It is explicitly not production-ready — breaking changes to config schema and APIs may still occur.

Beta ships when:
- All v1 scope items below are complete and stable on this homelab
- Single binary deployment works on Linux amd64 + arm64
- Docker image published
- Install docs written for a fresh server
- Known critical bugs resolved

### Stable (`v1.0.0`)
Config schema and API contract frozen. Migration guides provided for any breaking changes from beta. Announced publicly.

---

## v1 Scope (MVP)

The full feature set above is the north star. A realistic v1 that's already better than both existing tools:

- [ ] YAML config with hot-reload
- [ ] HTTP, TCP, DNS, ping check types
- [ ] WebSocket real-time dashboard
- [ ] Dependency graph (config + interactive UI)
- [ ] Flap dampening + smart alert routing
- [ ] Slack / Discord / webhook notifications
- [ ] REST API with API keys
- [ ] SQLite history store
- [ ] Basic SLA % + response time charts
- [ ] Public status page
- [ ] Single binary deployment, ARM64 support

Everything else (screenshot on failure, incident replay, K8s CRD, PDF reports, multi-step checks) is v2+.
