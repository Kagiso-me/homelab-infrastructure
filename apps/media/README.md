# apps/media

Flux Kustomizations for media applications (Jellyfin, Sonarr, Radarr, etc.).

> **Status: Placeholder** — Media applications currently run on the Docker host (`10.0.10.20`), not on the Kubernetes cluster. See [docker/](../../docker/) for the Docker-based media stack.
>
> This directory is reserved for future migration of media workloads to Kubernetes if desired.

If you decide to migrate media apps to k8s, the pattern follows [apps/base/grafana/](../base/grafana/) — create a base Kustomization with IngressRoute, then overlay in [apps/prod/](../homelab/).
