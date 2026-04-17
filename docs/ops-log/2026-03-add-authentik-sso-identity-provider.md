# 2026-03 — DEPLOY: Add Authentik SSO identity provider

**Operator:** Kagiso
**Type:** `DEPLOY`
**Components:** Authentik · OIDC · ForwardAuth · Traefik · PostgreSQL
**Commit:** —
**Downtime:** None (new deployment)

---

## What Changed

Deployed Authentik as the homelab's central identity provider. All external-facing services now authenticate through Authentik via Traefik ForwardAuth middleware — one login, all services.

---

## Why

Before Authentik, each service had its own authentication: Grafana had its own login, Nextcloud had its own login, n8n had its own login. Managing separate credentials for a dozen services is untenable. More importantly, several services (Longhorn, Prometheus) have no meaningful auth at all — they were either publicly exposed or hidden behind IP allowlisting.

Authentik provides a single sign-on layer: authenticate once, get a session cookie, access all services. It also adds MFA (TOTP), audit logs, and the ability to revoke access centrally.

---

## Details

- **Deployment**: upstream chart from `charts.goauthentik.io` (after custom chart was abandoned — see PR #8 ops-log)
- **Database**: shared PostgreSQL, `authentik` database
- **ForwardAuth middleware**: Traefik `ForwardAuth` middleware configured to check with Authentik outpost before forwarding requests
- **Outpost**: embedded outpost deployed alongside Authentik server
- **Applications configured**: Grafana, n8n, Nextcloud, Immich, Longhorn, Prometheus, Alertmanager, Seerr
- **MFA**: TOTP enforced for admin accounts
- **Branding**: custom homelab branding on login page

---

## Outcome

- Single sign-on across all protected services ✓
- MFA enabled and working ✓
- All services protected — no service is publicly accessible without auth ✓
- Authentik audit log capturing all authentication events ✓

---

## Related

- Authentik HelmRelease: `platform/security/authentik/helmrelease.yaml`
- ADR for SSO approach: `docs/adr/`
