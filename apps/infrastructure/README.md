# apps/infrastructure

Flux Kustomizations for infrastructure applications that are application-tier rather than platform-tier (e.g. Homer dashboard, Uptime Kuma if migrated to k8s).

> **Status: Placeholder** — No infrastructure applications are deployed here yet. Platform-level services (Prometheus, Loki, Traefik, cert-manager, etc.) live in [platform/](../../platform/) and are managed by Flux via the `infrastructure` Kustomization entry point.
