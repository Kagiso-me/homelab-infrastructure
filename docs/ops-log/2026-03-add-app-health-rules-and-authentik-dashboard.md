# 2026-03 — DEPLOY: Add app-health rules and Authentik dashboard

**Operator:** Kagiso
**Type:** `DEPLOY`
**Components:** Prometheus · Alertmanager · Grafana · Authentik
**Commit:** —
**Downtime:** None

---

## What Changed

Added Prometheus alerting rules for application health (pod restarts, OOMKilled, CrashLoopBackOff). Added a dedicated Grafana dashboard for Authentik showing authentication events, login failures, and active sessions.

---

## Why

The default kube-prometheus-stack rules cover node and cluster health well, but don't fire on application-specific issues. A pod restarting 50 times in an hour was invisible unless you happened to look at the workload summary. The new rules surface this immediately in Discord.

The Authentik dashboard was needed to distinguish "SSO is slow" from "SSO is broken" — Authentik's logs were the only place to find failed auth attempts and it required kubectl exec to read them.

---

## Details

**Alert rules added** (`platform/observability/prometheus/rules/app-health.yaml`):
- `PodCrashLooping` — fires if pod restarts > 5 in 15 minutes
- `PodOOMKilled` — fires on any OOMKilled event
- `DeploymentReplicasMismatch` — fires if desired != available replicas for > 5 minutes

**Authentik Grafana dashboard panels**:
- Successful logins per hour (by application)
- Failed login attempts (rate, by IP)
- Active sessions count
- Outpost health (embedded outpost latency)
- Token usage by application

---

## Outcome

- App health alerts firing correctly in test ✓
- Authentik dashboard showing auth activity ✓
- First real alert: PodCrashLooping on n8n (misconfigured env var, fixed same day) ✓

---

## Related

- Alert rules: `platform/observability/prometheus/rules/app-health.yaml`
- Authentik dashboard: `platform/observability/grafana-dashboards/authentik.json`
