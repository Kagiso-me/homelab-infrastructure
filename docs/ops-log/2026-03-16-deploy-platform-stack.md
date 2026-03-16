# 2026-03-16 — DEPLOY: Networking Platform Stack

**Operator:** Kagiso
**Type:** `DEPLOY`
**Components:** MetalLB v0.14 · cert-manager v1.14 · Traefik v3 (chart 28.3.0)
**Commit:** aa3486f
**Downtime:** None (initial install)

---

## What Changed

Deployed the full networking platform stack to the k3s cluster — MetalLB for load balancing,
cert-manager for TLS certificate management, and Traefik v3 as the ingress controller.
All three components installed via a single Ansible playbook in strict dependency order.

---

## Why

The cluster was running bare after initial provisioning. Without a load balancer, ingress
controller, and TLS automation, no applications could be securely exposed. This stack is
the prerequisite for all application deployments.

---

## Details

**MetalLB:**
- Mode: Layer-2 ARP
- IP pool: `10.0.10.110–10.0.10.125`
- Applied `IPAddressPool` and `L2Advertisement` CRDs after controller rollout

**cert-manager:**
- CRDs applied before Helm install
- Two `ClusterIssuers` created:
  - `letsencrypt-staging` — for testing, avoids rate limits
  - `letsencrypt` — production, used for live certificates
- Webhook readiness verified before issuer creation

**Traefik v3:**
- Helm chart version 28.3.0
- LoadBalancer IP pinned to `10.0.10.110`
- HTTP → HTTPS redirect enabled globally
- Prometheus metrics endpoint enabled (`/metrics` on port 9100)
- Resource limits: 100m CPU request / 300m limit, 128Mi memory request / 256Mi limit
- Dashboard disabled in production

**Issue encountered:**
Traefik install failed on first run. The Helm chart v28+ changed the `expose` field under
`ports` from a plain boolean to a structured object (`{default: true}`). The playbook values
file used the old boolean format, causing a template rendering error.

Fixed by updating the `ports` expose fields in the playbook to use the new object format.
See commit `aa3486f`.

**Playbook:**
- `ansible/playbooks/lifecycle/install-platform.yml`
- Tags allow selective reinstall: `--tags metallb`, `--tags cert-manager`, `--tags traefik`
- Includes post-install assertions: Traefik IP verification, pod status summary

---

## Outcome

- MetalLB controller and speaker pods healthy ✓
- cert-manager webhook ready ✓
- Traefik assigned `10.0.10.110` ✓
- Staging certificate issued successfully ✓
- HTTP → HTTPS redirect confirmed ✓

---

## Rollback

```bash
helm uninstall traefik -n traefik
helm uninstall cert-manager -n cert-manager
kubectl delete -f https://raw.githubusercontent.com/metallb/metallb/v0.14.0/config/manifests/metallb-native.yaml
kubectl delete ns traefik cert-manager metallb-system
```

---

## Related

- Playbook: `ansible/playbooks/lifecycle/install-platform.yml`
- Guide: `docs/guides/03-Networking-Platform.md`
- Traefik chart breaking change: `expose` field type changed in v28
