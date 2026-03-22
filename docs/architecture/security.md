
# Architecture — Security

## Security Model Reference

This document describes the security posture of the platform: threat model, controls in place, and known accepted risks.

---

## Threat Model

The platform is a homelab on a private home network. The realistic threat surface is:

| Threat | Likelihood | Controls |
|--------|-----------|---------|
| Exposed service exploited via internet | Low (no direct internet exposure) | Router NAT, no public IPs |
| Compromised secret in Git | Medium (repository may be public or shared) | SOPS + age encryption |
| SSH brute force on node | Medium | fail2ban, key-only auth, non-standard port optional |
| Compromised container escaping to node | Low | k3s default seccomp, namespace isolation |
| Malicious Helm chart | Low | Charts from trusted community repos only |
| Insider / automation host compromise | Low | Automation host has full cluster access — protect it |

---

## Node Security Controls

Applied by Ansible playbooks in `playbooks/security/`:

| Control | Playbook | Effect |
|---------|----------|--------|
| Key-only SSH | ssh-hardening.yml | Password auth disabled |
| Root login disabled | ssh-hardening.yml | Direct root SSH blocked |
| UFW firewall | firewall.yml | Only required ports open |
| fail2ban | fail2ban.yml | SSH brute force protection |
| Swap disabled | disable-swap.yml | Required by Kubernetes; also prevents swap-based attacks |
| NTP time sync | time-sync.yml | Prevents certificate/token time-skew attacks |

---

## Kubernetes RBAC

The platform uses Kubernetes RBAC to limit what service accounts can do.

Principles:

- Platform controllers (Flux, Velero, cert-manager) run with dedicated ServiceAccounts scoped to their required permissions.
- Application workloads run with the default ServiceAccount unless they explicitly need cluster access.
- `automountServiceAccountToken: false` is set on workloads that do not need API access.

Cluster-admin access is limited to:

- The automation host kubeconfig (for bootstrapping)
- Flux controllers (required for reconciliation)

---

## Secret Management

See [ADR-004](../adr/ADR-004-sops-age-secrets.md) and [Guide 03: Secrets Management](../guides/03-Secrets-Management.md).

Summary:

- All secrets encrypted with SOPS + age before Git commit.
- Age private key stored only in: offline backup location + `sops-age` Secret in `flux-system`.
- No plaintext secrets in Git, CI/CD environment variables, or application logs.
- Grafana default credentials changed on first deployment via encrypted Secret.

---

## Network Security

- No services are exposed directly to the internet. All ingress is via the home router with no port forwarding enabled by default.
- MetalLB IPs are on the local network only (10.0.10.0/24).
- All HTTP traffic redirected to HTTPS by Traefik middleware.
- TLS certificates issued by Let's Encrypt (external) or internal CA (internal-only services).
- Network policies are not currently enforced (accepted risk for homelab scale). If multi-tenant workloads are introduced, Calico or Cilium should replace Flannel for network policy enforcement.

---

## TLS Certificate Management

cert-manager automates the full certificate lifecycle:

- Issues certificates on `Ingress` / `IngressRoute` creation.
- Renews certificates 30 days before expiry.
- Stores private keys as Kubernetes Secrets (managed, not committed to Git).

Certificates are visible and their expiry monitored via Grafana. An alert fires when any certificate is within 14 days of expiry.

---

## Accepted Risks

| Risk | Rationale |
|------|-----------|
| No network policies | Homelab scale; all workloads trusted. Revisit if multi-tenant. |
| Single control-plane node | No HA; acceptable for homelab. Node failure requires rebuild. |
| Age private key loss = secret loss | Mitigated by offline backup requirement. |
| Automation host = full cluster access | Mitigated by securing the automation host itself. |
| No runtime security scanning | Falco not deployed. Acceptable for homelab threat model. |

---

## Security Improvement Backlog

These controls are not currently implemented but should be considered for higher-assurance operation:

1. **Falco** — runtime security monitoring and anomaly detection.
2. **Network Policies** — Cilium or Calico for namespace-level traffic restriction.
3. **Pod Security Admission** — enforce `restricted` policy on application namespaces.
4. **Container image scanning** — Trivy or Grype in CI to catch known CVEs before deployment.
5. **Audit logging** — k3s API server audit log shipped to Loki.
