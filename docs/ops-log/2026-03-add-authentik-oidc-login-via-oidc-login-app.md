# 2026-03 — DEPLOY: Add Authentik OIDC login via oidc_login app

**Operator:** Kagiso
**Type:** `DEPLOY`
**Components:** Authentik · Nextcloud · OIDC · oidc_login
**Commit:** —
**Downtime:** Partial — Nextcloud login unavailable during configuration (~10 min)

---

## What Changed

Configured Nextcloud to authenticate via Authentik using the `oidc_login` Nextcloud app. Users no longer log into Nextcloud with a Nextcloud-native password — they are redirected to Authentik and back.

---

## Why

Nextcloud has its own user management system. Without OIDC, you need a separate Nextcloud password in addition to your Authentik/SSO credentials. Every app maintaining its own user database undermines the purpose of having a central identity provider. OIDC integration means Authentik is the single source of truth for all user accounts across all apps.

---

## Details

- **Nextcloud app**: `oidc_login` installed via Nextcloud app store, configured in `config.php`
- **Authentik provider**: OIDC provider created in Authentik with `openid`, `profile`, `email` scopes
- **Client credentials**: stored in SOPS-encrypted Nextcloud secret
- **Redirect URI**: `https://cloud.kagiso.me/apps/oidc_login/oidc`
- **config.php additions**:
  ```php
  'oidc_login_provider_url' => 'https://analytics.kagiso.me/application/o/nextcloud/',
  'oidc_login_client_id' => '<from secret>',
  'oidc_login_client_secret' => '<from secret>',
  'oidc_login_auto_redirect' => true,
  'oidc_login_disable_registration' => true,
  ```
- **User provisioning**: users auto-created on first OIDC login, mapped to Authentik groups

---

## Outcome

- Nextcloud login redirects to Authentik ✓
- User auto-provisioned on first login ✓
- Native password login disabled ✓
- Files and calendars accessible after OIDC login ✓

---

## Related

- Nextcloud HelmRelease: `apps/base/nextcloud/helmrelease.yaml`
- Authentik OIDC provider: configured in Authentik UI
