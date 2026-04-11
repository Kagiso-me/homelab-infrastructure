# ADR-013 — SOPS + age Encryption

**Status:** Accepted
**Date:** 2026-01-15
**Deciders:** Kagiso

---

## Context

A GitOps platform requires all cluster state — including secrets — to be stored in Git.
Storing plaintext credentials in a repository (even a private one) is not acceptable.
Three approaches were evaluated:

1. **SOPS + age** — encrypt secret files at rest in Git; Flux decrypts at apply time
2. **Sealed Secrets** — Kubernetes controller encrypts secrets with a cluster-specific key; encrypted `SealedSecret` CRs are safe to commit
3. **External Secrets Operator (ESO)** — secrets live in an external vault (e.g. HashiCorp Vault, AWS Secrets Manager); ESO syncs them into the cluster at runtime

---

## Decision

**SOPS with age encryption.**

All files matching `*secret*.yaml` under `platform/`, `apps/`, and `clusters/`, plus any
`.yaml` file under a `secrets/` directory, are encrypted in-place before committing.
Flux decrypts them at apply time using the age private key stored in `flux-system/sops-age`.

---

## Rationale

### SOPS + age over Sealed Secrets

Sealed Secrets encrypts with a controller keypair generated inside the cluster. This creates
a hard dependency: if the cluster is destroyed, the decryption key is gone unless explicitly
backed up. Rebuilding the cluster from Git would require re-sealing every secret with the new
key — defeating a core GitOps property (repo is the source of truth, cluster is replaceable).

age is a modern, simple encryption tool (no GPG keyring, no agents, no expiry complexity).
The age private key is stored once: in `sops-age` inside `flux-system`, and offline in a
secure location. The public key is committed to `.sops.yaml` — it can be rotated by
re-encrypting files with a new key.

Flux has first-class native SOPS support — no plugins, no sidecars. This was a deciding
factor in choosing FluxCD over ArgoCD (see ADR-002).

### SOPS + age over External Secrets Operator

ESO requires an external secrets store (Vault, AWS SSM, etc.) to be running and reachable
at all times. For a homelab this adds significant operational overhead: either running Vault
inside the cluster (which needs its own HA, unsealing, and backup strategy) or depending on
a cloud service (which adds cost and an external availability dependency).

SOPS requires no external services. The decryption key is in the cluster. A fresh cluster
can bootstrap itself from the Git repo without any external dependencies — this is the
correct model for a single-operator homelab that needs to be fully rebuildable.

### age over GPG

GPG requires a keyring, an agent, expiry management, and web-of-trust concepts that add
friction for a solo operator. age has no keyring — a key is just a file. `age-keygen`
produces a key pair in seconds. Encryption and decryption are single commands with no
configuration. SOPS supports age natively since v3.7.

---

## Key properties of the implementation

- **`.sops.yaml`** at the repo root defines which files are encrypted and with which public key
- **Pattern-based**: files are encrypted by filename pattern, not by explicit enumeration — new secrets are automatically caught if they match the pattern
- **Flux decrypts at apply time**: each `Kustomization` that contains secrets specifies `spec.decryption.provider: sops` and references the `sops-age` secret
- **The age private key never touches Git**: it is generated once, stored in the cluster, and kept offline as a backup
- **Key rotation**: re-encrypt all secrets with `sops updatekeys` when the key needs to change

---

## Consequences

- All secrets in Git are encrypted. A repo leak exposes no credentials.
- The cluster is fully rebuildable from Git — Flux bootstraps, loads the age key, and decrypts all secrets without manual intervention.
- The age private key is a single point of failure — if lost without a backup, all secrets must be rotated and re-encrypted. Offline backup is mandatory.
- Editing a secret requires `sops path/to/secret.yaml` — no plaintext files on disk.
- Secret values are never visible in `git diff` or `git log`.
