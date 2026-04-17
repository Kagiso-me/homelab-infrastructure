# 2026-03 — DEPLOY: Configure Resend SMTP for transactional email

**Operator:** Kagiso
**Type:** `DEPLOY`
**Components:** Resend · SMTP · Authentik · Nextcloud
**Commit:** —
**Downtime:** None

---

## What Changed

Initial configuration of Resend as the SMTP relay for homelab transactional email. This was the first pass — Authentik and Nextcloud wired up, Vaultwarden added in a later iteration.

---

## Why

See the more detailed entry: [2026-04 — Wire Resend SMTP into Nextcloud, Vaultwarden, and Authentik](2026-04-wire-resend-smtp-into-nextcloud-vaultwarden-and-authentik.md)

This earlier entry covers the initial domain verification in Resend and the first two app configurations.

---

## Details

- **Resend domain verification**: `kagiso.me` verified via DNS TXT records in Cloudflare
- **From address**: `homelab@kagiso.me`
- **Apps configured (first pass)**: Authentik, Nextcloud
- **Vaultwarden**: added in follow-up pass after confirming initial configuration worked

---

## Outcome

- Resend domain verified ✓
- Authentik and Nextcloud email confirmed working ✓

---

## Related

- Full SMTP wiring: `docs/ops-log/2026-04-wire-resend-smtp-into-nextcloud-vaultwarden-and-authentik.md`
