# 2026-03 — FIX: Switch Velero kubectl init container from bitnami/kubectl to registry.k8s.io/kubectl

**Operator:** Kagiso
**Type:** `FIX`
**Components:** Velero · Bitnami · Docker Hub · registry.k8s.io
**Commit:** —
**Downtime:** None (Velero CRD upgrade unblocked)

---

## What Changed

Changed Velero's kubectl init container image from `docker.io/bitnami/kubectl` to `registry.k8s.io/kubectl:v1.32.0`.

---

## Why

Bitnami stopped publishing free images to Docker Hub. Their images now require authentication to pull, and unauthenticated pulls return a `not found` (404) error rather than an auth error — which makes it look like the image doesn't exist rather than that access was denied. The Velero upgrade job uses a kubectl init container to apply CRDs before Velero starts, and it was silently failing every time the cluster tried to pull the init container image.

The fix is straightforward: use the official `registry.k8s.io/kubectl` image, which is published by the Kubernetes project itself and has no pull restrictions.

---

## Details

- Old image: `docker.io/bitnami/kubectl:latest`
- New image: `registry.k8s.io/kubectl:v1.32.0`
- Set in Velero HelmRelease values under `kubectl.image`
- Velero CRD upgrade job completed successfully on next reconcile
- This affects anyone using Bitnami images from Docker Hub without authentication — the error message is deliberately misleading

---

## Outcome

- Velero CRD upgrade job completed successfully ✓
- Velero pod running and taking backups ✓
- Removed implicit dependency on Docker Hub unauthenticated pulls ✓

---

## Rollback

Not applicable — Bitnami images on Docker Hub are no longer publicly accessible.

---

## Related

- Bitnami Docker Hub announcement: rate limits and auth requirements introduced Q4 2023
- Velero HelmRelease: `platform/backups/velero/helmrelease.yaml`
- Alternative: pull Bitnami images from `registry.bitnami.com` (still requires account)
