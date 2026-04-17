# 2026-03 — DEPLOY: Standardise metrics to job-label scheme, add dashboard and Docker backend

**Operator:** Kagiso
**Type:** `DEPLOY`
**Components:** Prometheus · node-exporter · ServiceMonitor · Docker · varys
**Commit:** —
**Downtime:** None

---

## What Changed

Standardised all Prometheus scrape job labels to a consistent `job="<service-name>"` scheme across cluster and host metrics. Added a Docker metrics backend (cAdvisor on varys) and rebuilt the base dashboard to use the new label scheme.

---

## Why

Prometheus metrics from different components were using inconsistent job labels — some used the ServiceMonitor name, some used the Helm release name, some were auto-generated. Writing PromQL queries required knowing which naming convention each component used. The standardisation makes queries predictable: `job="node-exporter"` always means node metrics, `job="kube-state-metrics"` always means Kubernetes object metrics.

Docker container metrics on varys (Plex, media stack) were invisible in Prometheus — only host-level metrics from node-exporter. cAdvisor adds per-container CPU/memory metrics.

---

## Details

- **Job label standardisation**: all ServiceMonitors updated to use `jobLabel` or `relabeling` to produce consistent `job=` values
- **cAdvisor on varys**: deployed as privileged Docker container (`gcr.io/cadvisor/cadvisor`), scrapes Docker daemon socket
- **Static scrape target**: Prometheus static config for `varys:8080` (cAdvisor) with `job="cadvisor-varys"` label
- **Dashboard updated**: variables use `job` label for filtering, panels updated to use standardised labels

---

## Outcome

- All Prometheus metrics use consistent job labelling ✓
- Docker container metrics for varys visible in Prometheus ✓
- PromQL queries simplified — no more per-component label archaeology ✓

---

## Related

- Prometheus config: `platform/observability/kube-prometheus-stack/helmrelease.yaml`
- cAdvisor: `host-services/varys/monitoring/docker-compose.yml`
