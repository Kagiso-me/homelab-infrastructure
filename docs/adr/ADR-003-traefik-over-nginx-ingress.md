
# ADR-003 — Traefik over nginx-ingress

**Status:** Accepted
**Date:** 2026-01-15
**Deciders:** Platform team

---

## Context

The platform requires an ingress controller to route HTTP/HTTPS traffic from the MetalLB-assigned IP into cluster services. The two most common options for self-hosted Kubernetes are Traefik and nginx-ingress.

## Decision

**Traefik was selected.**

## Rationale

| Criterion | Traefik | nginx-ingress |
|-----------|---------|---------------|
| Dynamic configuration reload | Yes (no restart required) | Limited |
| Built-in dashboard | Yes | No |
| Prometheus metrics | Native | Via annotations |
| TLS cert-manager integration | Excellent | Good |
| IngressRoute CRD | Yes (advanced routing) | No |
| Middleware support | Rich (rate limiting, auth, headers) | Annotation-based |
| Bundled with k3s | Yes (as optional default) | No |

**Key deciding factors:**

1. **Dynamic configuration.** Traefik watches Kubernetes resources and reconfigures itself without a restart. In practice this means adding a new ingress route takes effect immediately without disruption to existing traffic.

2. **Native Prometheus metrics.** Traefik exposes detailed per-route request metrics out of the box. This feeds directly into the platform's Prometheus + Grafana monitoring stack without additional configuration.

3. **IngressRoute CRD.** The `IngressRoute` resource provides capabilities (per-route middleware, TCP routing, weighted routing) that cannot be achieved with standard Kubernetes Ingress annotations. For a production-style platform, this expressiveness is valuable.

4. **k3s familiarity.** k3s bundles Traefik as its default ingress. The platform disables the bundled version in favour of a Flux-managed Helm deployment (for version control), but the operational familiarity with Traefik in the k3s context is a practical advantage.

## Consequences

- All ingress resources use either standard Kubernetes `Ingress` (for portability) or Traefik `IngressRoute` (for features).
- The k3s bundled Traefik is disabled at install time. The platform manages Traefik via a `HelmRelease` under `infrastructure/controllers/traefik/`.
- Traefik's dashboard is exposed on a separate IngressRoute with access controls.
- cert-manager integration uses `tls.certResolver` in IngressRoute or `cert-manager.io/cluster-issuer` annotation in standard Ingress resources.

---
