# 2026-04 — DEPLOY: Deploy Vaultwarden + roadmap cleanup

**Operator:** Kagiso
**Type:** `DEPLOY`
**Components:** Vaultwarden · PostgreSQL · SOPS
**Commit:** —
**Downtime:** None

---

## What Changed

Deployed Vaultwarden (self-hosted Bitwarden-compatible password manager) to the cluster using the shared PostgreSQL instance. Also cleaned up completed items from the roadmap.json.

---

## Why

Using a cloud password manager (1Password, Bitwarden hosted) means your vault lives on someone else's infrastructure. Vaultwarden gives full self-hosted control — the same Bitwarden clients work against it. All family passwords, SSH keys, and TOTP secrets now live on the homelab, encrypted at rest, with S3 backup.

---

## Details

- **HelmRelease**: `vaultwarden` in `apps` namespace, upstream chart from `charts.gabe565.com`
- **Database**: `postgresql://vaultwarden@postgresql-primary.databases.svc.cluster.local/vaultwarden`
- **Admin panel**: blocked on external ingress (Traefik 403 middleware), accessible on `vault.local.kagiso.me/admin` only
- **Signups**: disabled (`SIGNUPS_ALLOWED=false`) — invites only
- **SMTP**: Resend relay configured for 2FA and emergency access emails
- **Backup**: Vaultwarden data directory included in Velero schedule
- **Clients**: Bitwarden browser extension and iOS app pointed at `https://vault.kagiso.me`

---

## Outcome

- Vaultwarden running, accessible at `vault.kagiso.me` ✓
- Admin panel blocked externally, accessible internally ✓
- Bitwarden clients syncing ✓
- SMTP email confirmed working (test 2FA email received) ✓

---

## Related

- Vaultwarden HelmRelease: `apps/base/vaultwarden/helmrelease.yaml`
- Admin path blocking: `docs/ops-log/2026-04-block-admin-paths-on-external-ingress-for-vaultwarden-and-authentik.md`
