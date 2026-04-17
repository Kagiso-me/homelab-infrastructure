# 2026-04 — DEPLOY: Switch to official upstream Authentik chart (#8)

**Operator:** Kagiso
**Type:** `DEPLOY`
**Components:** Authentik · HelmRelease · HelmRepository
**Commit:** —
**Downtime:** Partial — Authentik was already broken (500 errors)

---

## What Changed

Replaced the in-house custom Authentik Helm chart with the official upstream chart from `charts.goauthentik.io`. See the detailed ops-log entry for this change.

---

## Why

See: [2026-04-05 — Switch authentik from custom chart to upstream official chart](../ops-log/2026-04-05-switch-authentik-upstream-chart.md)

---

## Outcome

- Authentik healthy on upstream chart ✓
- All SSO flows working ✓
- PR #8 merged ✓
