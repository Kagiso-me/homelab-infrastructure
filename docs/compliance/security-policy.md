# Security Policy

## Document Control

| Field        | Value             |
|--------------|-------------------|
| Version      | 1.0               |
| Date         | 2026-03-14        |
| Status       | Active            |
| Owner        | Platform Engineer |
| Review Cycle | Quarterly         |

---

## 1. Purpose and Scope

This Security Policy defines the security controls, standards, and accepted risks for the homelab Kubernetes infrastructure. It governs the k3s cluster, associated storage, secrets management, network exposure, and the GitOps pipeline.

**In scope:**
- k3s cluster nodes: tywin (10.0.10.11), jaime (10.0.10.12), tyrion (10.0.10.13)
- Kubernetes workloads and namespaces managed by FluxCD
- TrueNAS storage (10.0.10.80) and NFS-backed persistent volumes
- External domain: kagiso.me (public-facing services)
- GitOps repository: github.com/\<user\>/homelab-infrastructure
- Secrets managed via SOPS + age encryption

**Out of scope:**
- Physical security of homelab hardware (assumed to be in a controlled residential environment)
- Upstream provider security (GitHub, Backblaze B2, Let's Encrypt)
- End-user device security

---

## 2. Network Security

### 2.1 Load Balancer and Ingress

| Control                          | Implementation                                                            |
|----------------------------------|---------------------------------------------------------------------------|
| External IP management           | MetalLB in Layer-2 mode; IPs allocated from reserved homelab pool         |
| Ingress controller               | Traefik, deployed via Helm chart managed by Flux                          |
| HTTPS enforcement                | Traefik configured to redirect all HTTP (port 80) to HTTPS (port 443)    |
| HTTP plaintext access            | Disabled for all public-facing services; HTTP-01 ACME challenge excepted  |
| NodePort exposure                | Not used; all external traffic routed through MetalLB + Traefik           |
| HostPort exposure                | Not used; avoided in all workload manifests                               |

All public-facing services are exposed exclusively via the Traefik ingress with TLS termination. Direct NodePort or HostPort exposure is prohibited unless explicitly documented with justification.

### 2.2 Network Segmentation

The homelab uses VLAN-based segmentation at the network layer:
- Kubernetes node traffic operates on the cluster VLAN (10.0.10.0/24)
- Storage traffic to TrueNAS operates on the storage VLAN (10.0.10.0/24)
- External traffic enters through the homelab router/firewall

Kubernetes NetworkPolicy CRDs are not enforced in this environment (see Section 7 — Accepted Risks). Pod-to-pod communication is unrestricted within the cluster network.

### 2.3 Firewall

External firewall rules are maintained at the homelab router. Only ports 80 and 443 are forwarded to the MetalLB ingress VIP. Kubernetes API server (6443) is not exposed externally.

---

## 3. Identity and Access Management

### 3.1 Kubernetes RBAC

| Control                              | Implementation                                                       |
|--------------------------------------|----------------------------------------------------------------------|
| RBAC enabled                         | Enforced by k3s; cannot be disabled                                  |
| Wildcard ClusterRoles                | Prohibited. No ClusterRole grants `*` verbs or `*` resources        |
| Least-privilege service accounts     | All workloads use dedicated ServiceAccounts with minimal permissions  |
| Default ServiceAccount token automount | Disabled on workloads that do not require API access               |
| ClusterAdmin binding scope           | Restricted to the Platform Engineer kubeconfig; not granted to apps  |

RBAC manifests are stored in the Git repository and applied via FluxCD. Manual RBAC modifications via `kubectl` are prohibited outside of emergency procedures (see Change Management Policy).

### 3.2 Secrets Management

All Kubernetes Secrets containing sensitive values (credentials, API keys, TLS private keys) are managed via SOPS + age encryption.

| Control                           | Implementation                                                         |
|-----------------------------------|------------------------------------------------------------------------|
| Encryption standard               | age (X25519 public-key encryption)                                     |
| Encrypted files committed to Git  | Yes; `.sops.yaml` defines encryption rules by path pattern            |
| Plaintext secrets in Git          | Prohibited. Pre-commit hooks and CI checks enforce this               |
| age private key storage           | Out-of-band; stored in password manager, not on cluster nodes         |
| Secret decryption in-cluster      | FluxCD SOPS provider decrypts at reconciliation time                  |
| etcd encryption at rest           | Enabled via k3s EncryptionConfiguration for Secret resources          |

### 3.3 Cluster Access

Cluster API access (kubeconfig) is restricted to the Platform Engineer. The kubeconfig is not committed to the Git repository. Remote kubeconfig access requires VPN or local network access; the API server is not internet-exposed.

---

## 4. TLS Policy

| Service Type           | Certificate Authority       | Certificate Management                   |
|------------------------|-----------------------------|------------------------------------------|
| Public services (kagiso.me) | Let's Encrypt (production)  | cert-manager with HTTP-01 ACME challenge |
| Cluster-internal services  | Internal CA (self-signed)   | cert-manager with internal Issuer        |
| k3s internal components    | k3s auto-generated CA       | Managed by k3s; rotated on cluster init  |

**Requirements:**
- Let's Encrypt production certificates are used for all public-facing services. The staging endpoint must not be used for live traffic.
- TLS certificates are provisioned and renewed automatically by cert-manager. Manual certificate management is not permitted.
- Certificate expiry is monitored by Prometheus/Alertmanager. An alert fires if a certificate expiry is within 14 days and cert-manager has not renewed it.
- Minimum TLS version: 1.2. TLS 1.0 and 1.1 are disabled in Traefik configuration.

---

## 5. Container Image Policy

| Control                         | Requirement                                                                |
|---------------------------------|----------------------------------------------------------------------------|
| Image tag `latest`              | Prohibited in all workload manifests                                       |
| Image digest pinning            | Recommended for critical workloads; enforced via Flux ImagePolicy where applicable |
| Image source                    | Official or well-maintained images from Docker Hub, GHCR, or Quay preferred |
| Private registry                | Not currently in use; all images pulled from public registries             |

The use of `latest` or untagged image references is prohibited because they prevent reproducible deployments and make rollback unreliable. All Helm chart values and raw manifests must specify explicit, pinned image tags.

### 5.1 Automated Image Updates

Flux ImageRepository and ImagePolicy resources are used where applicable to automate minor/patch version updates within defined semver constraints. All automated image update PRs are reviewed before merging to `main`.

### 5.2 Vulnerability Management

- Dependabot or Renovate Bot is configured (or intended to be configured) on the homelab-infrastructure repository to raise PRs for Helm chart and container image updates.
- There is no formal vulnerability scanning pipeline at present. This is an accepted risk in the homelab context (see Section 7).
- Security advisories for key components (k3s, Traefik, FluxCD) are monitored via GitHub Advisories and vendor release notes.

---

## 6. Incident Response

Given the single-operator nature of this homelab, the incident response process is intentionally lightweight.

### 6.1 Detection

Security incidents are detected via:
- Alertmanager notifications (anomalous pod activity, certificate failures, failed auth attempts in logs)
- Loki log queries for suspicious patterns
- Manual review of cluster events: `kubectl get events -A`

### 6.2 Response Steps

1. **Contain:** Isolate affected workload (scale to zero, suspend Flux reconciliation for affected namespace).
2. **Investigate:** Review Loki logs, Kubernetes audit logs (if enabled), and cluster events.
3. **Remediate:** Patch the vulnerability, rotate affected credentials, redeploy from clean Git state.
4. **Review:** Document the incident in `docs/compliance/incident-log.md`. Update policies or runbooks as needed.

### 6.3 Credential Rotation

If credentials (API keys, Velero MinIO credentials, TrueNAS API keys) are suspected to be compromised:
1. Rotate the credential at the source (MinIO, TrueNAS, external service).
2. Update the SOPS-encrypted Secret in the Git repository.
3. Force Flux reconciliation: `flux reconcile kustomization flux-system`.
4. Verify the new credential is active in the running workload.

---

## 7. Accepted Risks

The following risks are accepted given the homelab context and documented here for transparency.

| Risk                              | Rationale / Mitigation                                                     | Reference  |
|-----------------------------------|----------------------------------------------------------------------------|------------|
| Single control-plane node         | No etcd HA; accepted to reduce complexity and hardware cost. Mitigated by etcd snapshots and documented recovery runbook. | ADR-005    |
| No Kubernetes NetworkPolicy       | CNI does not enforce NetworkPolicy by default in this configuration. East-west traffic is unrestricted within the cluster. Mitigated by VLAN segmentation at network layer. | ADR-003    |
| No vulnerability scanning pipeline| No automated container image CVE scanning. Mitigated by staying current with upstream releases and monitoring advisories. | —          |
| No audit logging                  | Kubernetes API audit logging is not enabled. Reduces operational complexity at the cost of forensic capability. | —          |
| Homelab physical security         | Hardware is located in a residential environment; physical access controls are informal. | —          |

These risks are reviewed quarterly. If the environment evolves toward hosting sensitive data or externally-accessible production workloads, these risks must be formally reassessed.

---

## 8. Policy Compliance and Review

This policy applies to all infrastructure changes made to the homelab environment. Deviations require documentation of the rationale and a compensating control recorded in the relevant ADR or this document.

This policy is reviewed quarterly and after any security incident.

| Version | Date       | Author            | Summary of Changes     |
|---------|------------|-------------------|------------------------|
| 1.0     | 2026-03-14 | Platform Engineer | Initial document       |
