# 2026-04 — DEPLOY: Enable Grafana and Alertmanager in-cluster with Discord (#9)

**Operator:** Kagiso
**Type:** `DEPLOY`
**Components:** Grafana · Alertmanager · kube-prometheus-stack · Discord
**Commit:** —
**Downtime:** None (green-field install)

---

## What Changed

Enabled Grafana and Alertmanager as part of the `kube-prometheus-stack` HelmRelease. Configured Alertmanager to route all alerts to a Discord channel via webhook. Grafana exposed on `grafana.local.kagiso.me` behind Authentik.

---

## Why

Prometheus was scraping metrics but there was no way to visualise them or receive alerts. Running a monitoring stack without dashboards or alerting is just collecting data into a void. Grafana is the standard visualisation layer for Prometheus; Alertmanager with Discord means alerts land in a channel that's already open all day rather than requiring a separate pager tool.

---

## Details

- **Grafana**: enabled in kube-prometheus-stack values, persistence on NFS, admin password from SOPS secret, OAuth via Authentik
- **Alertmanager**: enabled, configured via `AlertmanagerConfig` CRD in `monitoring` namespace
- **Discord integration**: Alertmanager webhook receiver pointing at Discord channel webhook URL (stored in SOPS secret)
- **Alert routing**: all alerts → `#homelab-alerts` Discord channel, grouped by alertname with 5-minute group wait
- **Grafana dashboards**: node exporter, k3s, Flux, Velero dashboards pre-installed via ConfigMap provisioning
- **PR**: #9

---

## Outcome

- Grafana accessible at `grafana.local.kagiso.me` ✓
- Alertmanager routing alerts to Discord ✓
- Test alert fired and confirmed in Discord channel ✓
- Node and cluster dashboards showing data immediately ✓

---

## Related

- kube-prometheus-stack HelmRelease: `platform/observability/kube-prometheus-stack/helmrelease.yaml`
- AlertmanagerConfig: `platform/observability/kube-prometheus-stack/alertmanager-config.yaml`
