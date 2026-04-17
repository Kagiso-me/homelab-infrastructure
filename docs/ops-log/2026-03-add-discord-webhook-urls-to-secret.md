# 2026-03 — DEPLOY: Add Discord webhook URLs to secret

**Operator:** Kagiso
**Type:** `DEPLOY`
**Components:** Discord · Alertmanager · SOPS · secrets
**Commit:** —
**Downtime:** None

---

## What Changed

Added Discord webhook URLs to the SOPS-encrypted Alertmanager secret and wired them into the Alertmanager configuration. Alerts now route to specific Discord channels based on severity.

---

## Why

Alertmanager was configured but routing to a null receiver — alerts were being evaluated but not delivered anywhere. Discord is the communication layer already open all day; routing alerts there means they're noticed without needing a separate pager service.

---

## Details

- **Channels configured**:
  - `#homelab-alerts` — all alerts (default route)
  - `#homelab-critical` — critical severity only (separate webhook, louder visual)
- **Webhook URLs**: stored in SOPS secret `alertmanager-secret`, referenced in AlertmanagerConfig via `valuesFrom`
- **Routing**: severity label on alerts determines channel — `critical` → `#homelab-critical`, everything else → `#homelab-alerts`
- **Message format**: Alertmanager Discord template with alert name, description, labels, and runbook link
- **Grouping**: 5-minute group wait, 1-hour group interval (prevents alert storms)

---

## Outcome

- Test alert delivered to `#homelab-alerts` ✓
- Critical test alert delivered to `#homelab-critical` ✓
- Alert grouping working correctly (multiple alerts in one message) ✓

---

## Related

- AlertmanagerConfig: `platform/observability/kube-prometheus-stack/alertmanager-config.yaml`
- Secret: `platform/observability/kube-prometheus-stack/alertmanager-secret.yaml` (SOPS-encrypted)
