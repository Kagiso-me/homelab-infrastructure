# 2026-03-22 — CONFIG: Grafana Ingress Debugging and Staging Environment Fixes

**Operator:** Kagiso
**Type:** `CONFIG`
**Components:** Traefik · MetalLB · cert-manager · Flux · Grafana
**Commit:** e84df0b
**Downtime:** None

---

## What Changed

Three bugs in the staging cluster configuration were identified and fixed while bringing up
Grafana access for the first time. An environment access pattern was also established:
staging services are accessed directly by IP, prod services are accessed via domain name
with a trusted certificate.

---

## Why

Grafana was deployed and its IngressRoute was being reconciled by Flux, but the service
was unreachable. The root cause was a chain of three independent misconfigurations in the
staging cluster setup.

---

## Details

**Bug 1 — Flux healthCheck referenced wrong Deployment name**
- `clusters/staging/apps.yaml` had `healthChecks` pointing to a Deployment named `grafana`
- The actual Deployment created by kube-prometheus-stack is `kube-prometheus-stack-grafana`
- Flux was stuck in `Reconciliation in progress` for 2+ hours waiting for a Deployment that doesn't exist
- Fix: updated the healthCheck name to `kube-prometheus-stack-grafana`

**Bug 2 — Traefik LoadBalancer IP outside staging MetalLB pool**
- `platform/networking/traefik/helmrelease.yaml` pins Traefik to `10.0.10.110` (the prod IP)
- Staging MetalLB pool is `10.0.10.190–10.0.10.199` — `.110` is not in range
- MetalLB left Traefik with `EXTERNAL-IP: <pending>`, making all services unreachable
- Fix: added a patch in `clusters/staging/infrastructure.yaml` to override the Traefik annotation to `10.0.10.190` for staging

**Bug 3 — Flux apps Kustomization depended on wrong platform state (pre-existing)**
- `DependencyNotReady` events showed apps Kustomization blocked for 118 minutes before
  finally making progress — likely a timing issue during initial cluster bootstrap

**Environment access pattern established:**
- **Staging** — access services directly by IP (e.g. `https://10.0.10.190`)
  - Uses `letsencrypt-staging` issuer; browser cert warnings are expected and accepted
  - No Pi-hole DNS records needed for staging
- **Prod** — access services by domain name (e.g. `https://grafana.kagiso.me`)
  - Uses `letsencrypt-prod` issuer; trusted cert, no browser warnings
  - Pi-hole DNS records point to `10.0.10.110` (Traefik prod IP)

**Staging-specific patches in `clusters/staging/infrastructure.yaml`:**
- MetalLB `IPAddressPool`: `10.0.10.110–10.0.10.125` → `10.0.10.190–10.0.10.199`
- Traefik LoadBalancer annotation: `10.0.10.110` → `10.0.10.190`
- Wildcard Certificate issuer: `letsencrypt-prod` → `letsencrypt-staging`

---

## Outcome

- [x] Flux `apps` Kustomization reconciles successfully (`Ready: True`)
- [x] Grafana IngressRoute applied in `monitoring` namespace
- [x] Traefik assigned `10.0.10.190` from MetalLB staging pool
- [x] Grafana reachable at `https://10.0.10.190` (expected cert warning on staging)
- [x] Staging/prod access pattern documented and understood

---

## Rollback

To undo the Traefik IP patch (revert staging to broken state):
```bash
# Remove the patches block from platform-networking Kustomization in clusters/staging/infrastructure.yaml
flux reconcile kustomization platform-networking --with-source
```

To undo the healthCheck fix:
```bash
# Revert clusters/staging/apps.yaml healthCheck name back to "grafana"
# (this will break reconciliation again)
```

---

## Related

- `clusters/staging/infrastructure.yaml` — all staging-specific patches
- `clusters/staging/apps.yaml` — Flux apps Kustomization with healthChecks
- `platform/networking/traefik/helmrelease.yaml` — Traefik prod IP annotation
- `platform/networking/metallb-config/ip-pool.yaml` — prod MetalLB pool definition
- Guide: `docs/guides/05-Networking-MetalLB-Traefik.md`
