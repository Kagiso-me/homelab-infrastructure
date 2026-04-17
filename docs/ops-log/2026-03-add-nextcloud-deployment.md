# 2026-03 — DEPLOY: Add Nextcloud deployment

**Operator:** Kagiso
**Type:** `DEPLOY`
**Components:** Nextcloud · PostgreSQL · Redis · NFS · Collabora
**Commit:** —
**Downtime:** None (new deployment)

---

## What Changed

Deployed Nextcloud to the cluster — self-hosted file sync, calendar, contacts, and document editing. Uses shared PostgreSQL for the database, Redis for caching and locking, and NFS for file storage.

---

## Why

Google Drive and iCloud are convenient but mean all files, calendars, and contacts live on third-party infrastructure. Nextcloud gives the same sync across devices (iOS, desktop, web) with full data ownership. The CalDAV and CardDAV protocols mean the native iOS Calendar and Contacts apps sync to Nextcloud without needing the Nextcloud iOS app for everything.

---

## Details

- **Chart**: upstream Nextcloud chart from `nextcloud` Helm repo
- **Database**: PostgreSQL `nextcloud` on shared cluster instance
- **Cache**: Redis shared instance (also handles file locking — replaces default SQLite-based locking)
- **Storage**: NFS PVC (`nfs-truenas`) for data directory, 1Ti provisioned
- **SMTP**: Resend relay for notifications and password resets
- **Trusted proxies**: Traefik IP range added to `trusted_proxies` in config.php
- **Apps installed**: Calendar, Contacts, Notes, Talk (audio/video — disabled, too resource-heavy), Collabora Online (document editing)
- **External access**: `cloud.kagiso.me` via Traefik + Authentik

---

## Outcome

- Nextcloud running, initial setup completed ✓
- iOS files, calendar, and contacts syncing ✓
- Desktop client connected ✓
- Collabora document editing working ✓

---

## Related

- Nextcloud HelmRelease: `apps/base/nextcloud/helmrelease.yaml`
- SMTP: `docs/ops-log/2026-04-wire-resend-smtp-into-nextcloud-vaultwarden-and-authentik.md`
