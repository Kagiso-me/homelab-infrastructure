# 2026-03 — DEPLOY: Add encrypted Nextcloud secret

**Operator:** Kagiso
**Type:** `DEPLOY`
**Components:** Nextcloud · SOPS · age · secrets
**Commit:** —
**Downtime:** None

---

## What Changed

Created and SOPS-encrypted the Nextcloud Kubernetes secret containing database credentials, admin password, and SMTP configuration.

---

## Why

Nextcloud was initially bootstrapped with plaintext credentials during setup. The encrypted secret follows the same pattern established for all other app secrets: sensitive values encrypted at rest in the repository using SOPS+age, decrypted at reconcile time by Flux.

---

## Details

- **Secret keys encrypted**: `postgresql-password`, `nextcloud-admin-password`, `smtp-password`, `nextcloud-secret-key`
- **Secret name**: `nextcloud-secret` in `apps` namespace
- **nextcloud-secret-key**: 32-byte random hex string used by Nextcloud for session signing
- Flux decrypts at reconcile time, mounts into Nextcloud pod as environment variables

---

## Outcome

- Nextcloud secret encrypted and committed ✓
- Flux reconciling secret correctly ✓
- No plaintext credentials remaining for Nextcloud ✓

---

## Related

- Secret: `apps/base/nextcloud/secret.yaml` (SOPS-encrypted)
- SOPS setup: `docs/guides/sops-setup.md`
