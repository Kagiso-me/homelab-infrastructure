
# ADR-006 — Grafana Dashboard Suite

**Status:** Accepted
**Date:** 2026-03-22
**Deciders:** Platform team

---

## Context

Grafana is deployed on both staging and prod via kube-prometheus-stack. Prometheus scrapes
all cluster nodes, the Docker host, TrueNAS, and Proxmox. Loki collects logs from all
workloads via Promtail. The goal is a complete, opinionated set of dashboards that give full
visibility into every layer of the homelab — from ZFS disk health and Velero backup status
down to individual pod resource usage and Traefik request latency.

All dashboards below are imported from [grafana.com](https://grafana.com/grafana/dashboards)
by ID. No custom dashboards are required to get started.

---

## Decision

Import the following dashboards, organised by domain. Each entry includes the dashboard ID,
the data source it requires, and what it shows.

---

## Dashboard Registry

### Infrastructure — Nodes & Hardware

| ID | Name | Data Source | What it shows |
|----|------|-------------|---------------|
| **1860** | Node Exporter Full | Prometheus | The gold standard. CPU, memory, disk I/O, network throughput, load average, file descriptors — per node. Use this for bran, tywin, jaime, tyrion, docker-vm, and the RPi. |
| **13978** | Node Exporter Quickstart | Prometheus | Condensed single-page view of all nodes side-by-side. Good for a wall display or quick triage. |
| **14282** | cAdvisor Exporter | Prometheus | Container-level CPU, memory, and network on the Docker host (docker-vm, 10.0.10.32). Requires the cAdvisor exporter already scraping on `:8080`. |

---

### Storage — TrueNAS, ZFS & Disk Health

| ID | Name | Data Source | What it shows |
|----|------|-------------|---------------|
| **10664** | Smartctl Exporter | Prometheus | S.M.A.R.T. data for every physical drive — reallocated sectors, power-on hours, temperature, pending sectors, uncorrectable errors. Essential for early drive failure detection. Requires `smartctl-exporter` scrape target on `10.0.10.80:9633`. |
| **1860** | Node Exporter Full (TrueNAS instance) | Prometheus | Disk read/write latency, IOPS, and throughput per ZFS pool device. Filter to `instance="truenas"`. |

> **ZFS-specific metrics:** TrueNAS SCALE does not expose ZFS arc/pool metrics via node-exporter
> by default. If you want ZFS arc hit rate, pool capacity, and scrub status, install
> `zfs-exporter` on TrueNAS and add it as a scrape target. Dashboard ID **13852** (ZFS exporter)
> then gives full ZFS visibility.

---

### Kubernetes — Cluster & Workloads

| ID | Name | Data Source | What it shows |
|----|------|-------------|---------------|
| **15757** | Kubernetes / Views / Global | Prometheus | Top-level cluster health: node count, pod count, CPU/memory utilisation across the cluster. Best landing page dashboard. |
| **15758** | Kubernetes / Views / Namespaces | Prometheus | Per-namespace resource usage — CPU requests vs limits, memory consumption, pod restarts. |
| **15759** | Kubernetes / Views / Nodes | Prometheus | Per-node CPU, memory, disk, and network — kubernetes-aware (shows pod density per node). |
| **15760** | Kubernetes / Views / Pods | Prometheus | Per-pod CPU and memory with requests/limits overlaid. Drill down from namespace or node views. |
| **315** | Kubernetes cluster monitoring | Prometheus | Classic cluster monitoring dashboard — API server latency, scheduler, etcd, node conditions. |
| **6417** | Kubernetes Pods | Prometheus | Pod-level CPU, memory, restarts, and network — filterable by namespace and pod name. |

---

### GitOps — Flux

| ID | Name | Data Source | What it shows |
|----|------|-------------|---------------|
| **16714** | Flux Cluster Stats | Prometheus | Kustomization and HelmRelease reconciliation status, sync failures, drift detection, and controller resource usage. Critical for knowing if Flux is healthy without running `flux get kustomizations`. |

---

### Networking — Traefik & MetalLB

| ID | Name | Data Source | What it shows |
|----|------|-------------|---------------|
| **17347** | Traefik v3 | Prometheus | Request rate, error rate, P50/P95/P99 latency per router and service, active connections, TLS handshake rate. The primary dashboard for ingress health. |
| **9628** | MetalLB | Prometheus | IP address pool utilisation, BGP session status (not applicable — L2 mode only), address allocation events. |

---

### Monitoring Stack — Prometheus & Alertmanager

| ID | Name | Data Source | What it shows |
|----|------|-------------|---------------|
| **3662** | Prometheus Stats | Prometheus | Scrape duration, sample ingestion rate, TSDB compaction, WAL replay time, query performance. Use this to monitor the monitor. |
| **9578** | Alertmanager | Prometheus | Active alerts by severity, alert firing rate, silences, inhibition rules. Useful for knowing the alerting pipeline is functioning. |

---

### Logs — Loki

| ID | Name | Data Source | What it shows |
|----|------|-------------|---------------|
| **13639** | Loki Dashboard | Loki | Log volume by namespace, label exploration, and log stream browser. Starting point for log-based investigation. |
| **15141** | Kubernetes / Logs / Pod Logs | Loki | Pod log viewer with namespace and pod dropdowns. Integrates with the Kubernetes views dashboards for drill-down. |

---

### Backups — Velero

| ID | Name | Data Source | What it shows |
|----|------|-------------|---------------|
| **16980** | Velero Stats | Prometheus | Backup job success/failure rate, backup duration, last successful backup timestamp per schedule, restore operations. This is the most important dashboard to have alerting wired to — a silent backup failure is a disaster waiting to happen. |

---

### Proxmox Hypervisor

| ID | Name | Data Source | What it shows |
|----|------|-------------|---------------|
| **10347** | Proxmox VE | Prometheus | VM CPU, memory, disk, and network per node and per VM. Requires `pve-exporter` running on Proxmox. See note below. |

> **Proxmox scrape setup:** Proxmox does not expose Prometheus metrics natively. Install
> `prometheus-pve-exporter` on Proxmox (10.0.10.30) and add it as a scrape target in
> `platform/observability/kube-prometheus-stack/helmrelease.yaml` under `additionalScrapeConfigs`.
> Use port `9221` by convention.

---

## Import Procedure

1. In Grafana, navigate to **Dashboards → Import**
2. Enter the dashboard ID from the table above
3. Click **Load**
4. Select the correct data source (Prometheus or Loki) when prompted
5. Click **Import**

Repeat for each dashboard. Organise them into folders:

```
Dashboards/
├── Infrastructure/     ← Node Exporter, cAdvisor
├── Storage/            ← Smartctl, ZFS
├── Kubernetes/         ← Cluster views, Flux, Pods
├── Networking/         ← Traefik, MetalLB
├── Monitoring/         ← Prometheus, Alertmanager
├── Logs/               ← Loki dashboards
├── Backups/            ← Velero
└── Hypervisor/         ← Proxmox
```

---

## Alerting Priorities

Once dashboards are imported, wire alerts to these panels first — they represent the highest
blast radius if missed silently:

| Priority | Dashboard | Panel | Why |
|----------|-----------|-------|-----|
| 🔴 P1 | Velero Stats (16980) | Last successful backup | Silent backup failure = no recovery |
| 🔴 P1 | Smartctl (10664) | Reallocated sectors / pending sectors | Early drive failure signal |
| 🔴 P1 | Node Exporter Full (1860) | Disk usage % | Pool full = data loss on TrueNAS |
| 🟠 P2 | Flux Stats (16714) | Reconciliation failures | Drift from desired state undetected |
| 🟠 P2 | Kubernetes Views (15757) | Pod restarts | CrashLoopBackOff going unnoticed |
| 🟡 P3 | Traefik (17347) | Error rate | 5xx spike on ingress |
| 🟡 P3 | Prometheus Stats (3662) | Scrape failures | Blind spots in monitoring coverage |

---

## Future Dashboards (not yet available / requires additional exporters)

| What | Requires | Notes |
|------|----------|-------|
| Plex media server metrics | `Tautulli` or `exportarr` | Stream count, transcoding load, library size |
| SABnzbd download queue | `sabnzbd-exporter` | Queue depth, speed, failed downloads |
| Pi-hole DNS metrics | Pi-hole built-in Prometheus endpoint | Query rate, block rate, top domains |
| UPS power metrics | `nut-exporter` | Battery health, input voltage, load % |

---

## Consequences

**Positive:**
- Complete visibility across all homelab layers from a single Grafana instance
- All dashboards are community-maintained and update independently of this repo
- No custom dashboard JSON to version-control or maintain

**Negative:**
- Dashboard IDs on grafana.com are community contributions — some may become stale or
  unmaintained over time. Re-evaluate annually.
- Proxmox and ZFS dashboards require additional exporters not yet deployed.
