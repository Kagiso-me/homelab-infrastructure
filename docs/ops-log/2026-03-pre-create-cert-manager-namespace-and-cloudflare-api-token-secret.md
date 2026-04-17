# 2026-03 — DEPLOY: Pre-create cert-manager namespace and Cloudflare API token secret

**Operator:** Kagiso
**Type:** `DEPLOY`
**Components:** cert-manager · Cloudflare · SOPS · Ansible
**Commit:** —
**Downtime:** None

---

## What Changed

Added Ansible tasks to pre-create the `cert-manager` namespace and the Cloudflare API token Kubernetes secret before Flux bootstraps the cluster. This removes a chicken-and-egg problem in the bootstrap sequence.

---

## Why

cert-manager needs a `ClusterIssuer` that references a Kubernetes secret containing the Cloudflare API token (for DNS-01 ACME challenges). Flux creates the `ClusterIssuer` as part of the platform kustomization, but if the secret doesn't exist yet, the `ClusterIssuer` fails to reconcile. The namespace also needs to exist before any resources in it can be created.

By pre-creating both with Ansible during the initial cluster provision (before Flux runs), the bootstrap sequence becomes reliable and idempotent.

---

## Details

- **Ansible tasks** added to `bootstrap-cluster.yml`:
  1. Create `cert-manager` namespace
  2. Create `cloudflare-api-token-secret` in `cert-manager` namespace from vault variable
- **Secret**: `kubectl create secret generic cloudflare-api-token-secret --from-literal=api-token=<token>`
- **Token**: Cloudflare API token scoped to `Zone:DNS:Edit` on `kagiso.me` zone only (least-privilege)
- **Token storage**: Ansible Vault, not SOPS — used during bootstrap before Flux age key is installed

---

## Outcome

- cert-manager namespace and token pre-created before Flux runs ✓
- Bootstrap sequence reliable and repeatable ✓
- cert-manager `ClusterIssuer` reconciles immediately after Flux deploys it ✓

---

## Related

- Bootstrap playbook: `ansible/playbooks/bootstrap-cluster.yml`
- cert-manager ClusterIssuer: `platform/networking/cert-manager/clusterissuer.yaml`
