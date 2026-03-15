# Monitoring and Observability Architecture

## Overview

The observability stack is deployed in the `monitoring` namespace and is considered load-bearing platform infrastructure, not an optional add-on. All platform components expose metrics via ServiceMonitors. Log aggregation covers all workloads cluster-wide via Promtail DaemonSet.

---

## Components

| Component | Role | Key Configuration |
|---|---|---|
| **Prometheus** | Metrics collection and storage | Scrape interval: 30s; Retention: 15 days / 20 GB limit; Remote-write not configured |
| **Grafana** | Metrics visualisation and dashboards | Provisioned via ConfigMaps managed by FluxCD; persistent storage on `nfs-truenas` |
| **Alertmanager** | Alert routing and deduplication | Routes to Slack (warnings and criticals) and webhook (criticals only); Watchdog heartbeat to `watchdog-webhook` |
| **Loki** | Log aggregation | Retention: 14 days; Single-binary mode; Persistent storage on `nfs-truenas` |
| **Promtail** | Log shipping | DaemonSet on all nodes; scrapes `/var/log/pods` and `/var/log/journal`; ships to Loki |

---

## Alert Routing

All alerts flow from Prometheus through Alertmanager. Routing is determined by alert severity label.

```
Prometheus
    |
    | (fires alert)
    v
+------------------+
|  Alertmanager    |
+--------+---------+
         |
    +----+-------------------------------+
    |                                   |
    | severity = warning                | severity = critical
    v                                   v
+-------------------+         +---------+-----------+
| Slack             |         | Slack               |
| #homelab-alerts   |         | #homelab-critical   |
+-------------------+         |                     |
                              | Webhook endpoint    |
                              | (critical receiver) |
                              +---------------------+

Special route:
+------------------+
|  Watchdog alert  |  (always-firing heartbeat from Prometheus)
|  (alertname=     |
|   Watchdog)      |
+--------+---------+
         |
         v
+------------------+
| watchdog-webhook |  (external deadman switch / uptime checker)
+------------------+
```

**Routing rules summary:**

| Condition | Destination |
|---|---|
| `severity: warning` | Slack `#homelab-alerts` |
| `severity: critical` | Slack `#homelab-critical` + critical webhook |
| `alertname: Watchdog` | `watchdog-webhook` only (suppressed from Slack) |
| All others | Default receiver (Slack `#homelab-alerts`) |

**Inhibition rules:** Critical alerts inhibit their corresponding warning-severity counterparts to reduce noise during active incidents.

---

## Key Dashboards

All dashboards are provisioned as Grafana ConfigMaps and are restored automatically on cluster rebuild.

| Dashboard | Source | Purpose |
|---|---|---|
| **Node Metrics** | `node-exporter-full` (community) | Per-node CPU, memory, disk I/O, network throughput, filesystem usage |
| **Kubernetes Cluster Overview** | `kubernetes-cluster` (kube-prometheus-stack) | Pod counts, deployment health, resource requests vs limits, PVC status |
| **Velero Backup Status** | Custom | Last backup timestamp, success/failure per schedule, backup size trend |
| **Loki Logs** | Grafana Explore / Loki datasource | Ad-hoc log querying; no persistent dashboard — use Explore with LogQL |
| **Alertmanager Overview** | Bundled with kube-prometheus-stack | Active alerts, silences, receiver health |

---

## ServiceMonitor Coverage

Every platform component is required to have `serviceMonitor: true` (or equivalent) in its HelmRelease values. The table below confirms coverage for all platform components.

| Component | Namespace | ServiceMonitor Present |
|---|---|---|
| Prometheus | `monitoring` | Yes (self-scraped) |
| Grafana | `monitoring` | Yes |
| Alertmanager | `monitoring` | Yes |
| Loki | `monitoring` | Yes |
| Promtail | `monitoring` | Yes |
| Traefik | `traefik` | Yes |
| MetalLB (controller + speaker) | `metallb-system` | Yes |
| cert-manager | `cert-manager` | Yes |
| Velero | `velero` | Yes |
| NFS Subdir Provisioner | `storage` | Yes |
| system-upgrade-controller | `system-upgrade` | Yes |
| FluxCD controllers | `flux-system` | Yes |

> Any new platform component added to the cluster must include a ServiceMonitor as a merge requirement.

---

## Alert Runbook Index

Alert runbooks are stored in [`docs/operations/runbooks/alerts/`](../operations/runbooks/alerts/). Each runbook corresponds to one or more Alertmanager alert rules and documents triage steps, probable causes, and remediation actions.

| Alert Name | Runbook |
|---|---|
| `KubeNodeNotReady` | `runbooks/alerts/kube-node-not-ready.md` |
| `KubePodCrashLooping` | `runbooks/alerts/kube-pod-crash-looping.md` |
| `KubePersistentVolumeFillingUp` | `runbooks/alerts/pvc-filling-up.md` |
| `VeleroBackupFailed` | `runbooks/alerts/velero-backup-failed.md` |
| `PrometheusTargetMissing` | `runbooks/alerts/prometheus-target-missing.md` |
| `CertificateExpiringSoon` | `runbooks/alerts/certificate-expiring.md` |
| `HostHighCpuLoad` | `runbooks/alerts/host-high-cpu.md` |
| `HostOutOfMemory` | `runbooks/alerts/host-out-of-memory.md` |
| `HostOutOfDiskSpace` | `runbooks/alerts/host-out-of-disk-space.md` |
| `LokiRequestErrors` | `runbooks/alerts/loki-request-errors.md` |

---

## Known Gaps

| Gap | Detail | Priority |
|---|---|---|
| **No synthetic monitoring** | There are no external uptime probes (e.g., Blackbox Exporter HTTP checks, UptimeRobot). A service could be broken for external users while internal metrics appear healthy. | Medium |
| **No distributed tracing** | No tracing backend (Jaeger, Grafana Tempo) is deployed. Debugging latency across multiple services relies on logs and metrics alone. | Low |
| **No multi-site alerting redundancy** | Alertmanager is a single instance on the cluster. If the cluster is down, no alerts fire. The Watchdog heartbeat to `watchdog-webhook` partially mitigates this for full-outage scenarios. | Accepted |
| **Grafana auth** | Grafana is currently protected by Traefik basic-auth middleware. OAuth or SSO integration is not implemented. | Low |
