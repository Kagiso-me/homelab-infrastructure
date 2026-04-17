# 2026-04 — DEPLOY: Add node-exporter to all non-k3s hosts

**Operator:** Kagiso
**Type:** `DEPLOY`
**Components:** node-exporter · Prometheus · varys · bran · TrueNAS
**Commit:** —
**Downtime:** None

---

## What Changed

Deployed `node_exporter` as a Docker container on `varys` and as a systemd service on `bran`. Added static scrape targets to Prometheus for both hosts, plus the TrueNAS built-in metrics endpoint. All three now appear in Grafana's node dashboards alongside the k3s cluster nodes.

---

## Why

The k3s cluster nodes (jaime, tyrion, tywin) were already exporting metrics via the cluster's node-exporter DaemonSet. But `varys` (Docker host running media stack + Plex) and `bran` (RPi observer node running site CI) were invisible to Prometheus — no CPU, memory, disk, or network data. If varys was thrashing or bran was out of disk space, there was no alerting and no history. TrueNAS has a built-in Graphite/Prometheus endpoint that was simply never scraped.

---

## Details

- **varys**: `prom/node-exporter:v1.7.0` in `docker-compose.yml`, port `9100`, bind-mounted `/proc`, `/sys`, host network mode
- **bran**: `node_exporter` binary installed from GitHub release, systemd unit `node_exporter.service`, port `9100`
- **TrueNAS**: built-in metrics at `http://10.0.10.80:9100/metrics` (enabled in TrueNAS UI → Reporting → Reporting Exporters)
- Prometheus static configs added in `platform/monitoring/prometheus/config/`:
  ```yaml
  - job_name: 'node-varys'
    static_configs:
      - targets: ['10.0.10.x:9100']
        labels: { instance: 'varys' }
  - job_name: 'node-bran'
    static_configs:
      - targets: ['10.0.10.9:9100']
        labels: { instance: 'bran' }
  - job_name: 'node-truenas'
    static_configs:
      - targets: ['10.0.10.80:9100']
        labels: { instance: 'truenas' }
  ```
- Grafana "Node Exporter Full" dashboard (ID 1860) now shows all 6 hosts

---

## Outcome

- varys, bran, and TrueNAS all visible in Prometheus and Grafana ✓
- CPU, memory, disk I/O, and network metrics available for all non-k3s hosts ✓
- Alerting rules can now cover the full homelab, not just k3s nodes ✓

---

## Related

- Node exporter: `host-services/varys/docker-compose.yml`
- Prometheus scrape config: `platform/monitoring/prometheus/config/prometheus.yml`
