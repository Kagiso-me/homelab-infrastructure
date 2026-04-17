# 2026-04 — DEPLOY: Re-enable AlertmanagerConfig and secret for in-cluster Alertmanager

**Operator:** Kagiso
**Type:** `DEPLOY`
**Components:** Alertmanager · AlertmanagerConfig · kube-prometheus-stack · Discord
**Commit:** —
**Downtime:** None (alerts were silently dropping, not erroring)

---

## What Changed

Re-enabled the `AlertmanagerConfig` CRD and the associated secret after they were inadvertently removed during a kube-prometheus-stack upgrade. Discord alerts were silently dropping for approximately 3 days before noticed.

---

## Why

A kube-prometheus-stack Helm upgrade had removed the `AlertmanagerConfig` from the reconciled resources — likely because the upgrade changed the expected CRD version or namespace for the config. Alertmanager was running and evaluating rules but routing to a null receiver. No alerts were firing in Discord, which went unnoticed because there were no active alert conditions during that window.

Discovered when manually checking Alertmanager UI and noticing the routing config showed an empty receiver.

---

## Details

- Root cause: `AlertmanagerConfig` CRD moved from `monitoring` namespace to `default` in the chart upgrade — the old namespaced resource was silently ignored
- Fix: recreated `AlertmanagerConfig` in the correct namespace, re-added Discord webhook secret reference
- Added a Prometheus alert on Alertmanager itself: `AlertmanagerConfigNotLoaded` — fires if Alertmanager has no active receivers configured
- Verified fix by triggering a test alert via `amtool alert add`

---

## Outcome

- AlertmanagerConfig re-enabled and routing to Discord ✓
- Meta-alert added to catch future routing failures ✓
- 3-day alert blind spot documented ✓

---

## Related

- AlertmanagerConfig: `platform/observability/kube-prometheus-stack/alertmanager-config.yaml`
- Meta-alert rules: `platform/observability/prometheus/rules/alertmanager-health.yaml`
