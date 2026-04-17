# 2026-04 — DEPLOY: Wire Resend SMTP into Nextcloud, Vaultwarden, and Authentik

**Operator:** Kagiso
**Type:** `DEPLOY`
**Components:** Resend · Nextcloud · Vaultwarden · Authentik · SMTP
**Commit:** —
**Downtime:** None

---

## What Changed

Configured Resend as the SMTP relay for Nextcloud, Vaultwarden, and Authentik. All three apps now send transactional email (password resets, 2FA codes, share notifications) through `smtp.resend.com` using an API key stored in SOPS-encrypted Kubernetes secrets.

---

## Why

All three apps had email sending disabled or misconfigured. Vaultwarden was silently failing to send 2FA emails (which makes it unusable as a password manager if you get locked out). Authentik couldn't send password reset flows. Without working email, these apps are degraded — you're one forgotten password away from a manual secret recovery.

Self-hosting an SMTP server (Postfix, Maddy) is complex and likely to end up on spam blocklists. Resend provides a free tier with 3,000 emails/month, which is more than sufficient for a homelab, and handles deliverability properly.

---

## Details

- **Provider**: Resend (`smtp.resend.com:465`, TLS)
- **From address**: `homelab@kagiso.me` (Resend-verified domain)
- **Auth**: API key stored in SOPS-encrypted secret `resend-smtp-secret` in `apps` namespace
- **Nextcloud**: set via `mail_smtphost`, `mail_smtpport`, `mail_smtpauth`, `mail_smtpname`, `mail_smtppassword` in `config.php` override
- **Vaultwarden**: set via env vars `SMTP_HOST`, `SMTP_PORT`, `SMTP_USERNAME`, `SMTP_PASSWORD`, `SMTP_FROM`
- **Authentik**: set via HelmRelease values `email.host`, `email.port`, `email.username`, `email.password`, `email.from`
- All three tested: sent test email, confirmed delivery

---

## Outcome

- Vaultwarden 2FA and invite emails working ✓
- Authentik password reset flow working ✓
- Nextcloud share notifications working ✓
- All credentials SOPS-encrypted, not in plaintext ✓

---

## Related

- Resend docs: https://resend.com/docs/send-with-smtp
- SOPS secrets: `platform/security/resend-smtp-secret.yaml` (encrypted)
