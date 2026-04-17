# 2026-03 — DEPLOY: Add 6-hourly databases backup schedule

**Operator:** Kagiso
**Type:** `DEPLOY`
**Components:** Velero · databases namespace · Backblaze B2 · S3
**Commit:** —
**Downtime:** None

---

## What Changed

Added a dedicated Velero backup schedule for the `databases` namespace running every 6 hours, separate from the daily full-cluster backup. Backups stored in Backblaze B2 (S3-compatible).

---

## Why

The full-cluster daily backup covers everything including databases, but 24-hour RPO is too long for the databases namespace. PostgreSQL holds data for Nextcloud, Immich, Vaultwarden, n8n, and Authentik — losing up to 24 hours of data from any of these would be significant. 6-hour backups cut maximum data loss to 6 hours, which is acceptable.

Backblaze B2 is $0.006/GB/month — orders of magnitude cheaper than AWS S3 for small homelab-scale backup data.

---

## Details

- **Schedule**: `0 */6 * * *` (every 6 hours)
- **Included namespace**: `databases` only
- **Retention**: 7 days (28 backups retained at any time)
- **Storage**: Backblaze B2 bucket `homelab-velero-backups`, credentials in SOPS secret
- **BSL (BackupStorageLocation)**: `backblaze-b2`, S3-compatible endpoint `s3.us-west-004.backblazeb2.com`
- **Full cluster backup**: daily at 02:00, separate schedule, also to B2

---

## Outcome

- 6-hourly database backups running ✓
- First backup confirmed in B2 bucket ✓
- Restore tested: restored `databases` namespace to staging from a 6h backup ✓

---

## Related

- Velero schedule: `platform/backup/velero/schedules.yaml`
- BSL config: `platform/backup/velero/backupstoragelocation.yaml`
