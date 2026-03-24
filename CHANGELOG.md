# Changelog

All infrastructure changes are recorded here. One line per event — newest first.
Full details for each entry live in [`docs/ops-log/`](docs/ops-log/).

---

## How to Add an Entry

```
- **[TYPE]** Short description of what changed → [details](docs/ops-log/YYYY-MM-DD-slug.md)
```

Types: `DEPLOY` `UPGRADE` `CONFIG` `NETWORK` `STORAGE` `SCALE` `INCIDENT` `MAINTENANCE` `SECURITY` `HARDWARE`

---

## 2026-03
- **[CONFIG]** move backup dashboard from Docker provisioning to k8s ConfigMap `5d38ad9`
- **[DEPLOY]** standardise metrics to job-label scheme, add dashboard and Docker backup guide `6382b0c`
- **[DEPLOY]** add central PostgreSQL and Redis to platform — both pinned to control plane with local-path storage; shared across all apps (Nextcloud, Authentik, etc.); per-app databases provisioned via psql on deploy → [ADR-011](docs/adr/ADR-011-central-databases.md)
- **[CONFIG]** pivot alert notifications from Slack to Discord — unlimited message history on free tier, 2-minute webhook setup vs Slack app registration, identical Alertmanager config (Discord `/slack` endpoint accepts same payload). → [ADR-010](docs/adr/ADR-010-discord-over-slack.md)
- **[FIX]** move Prometheus TSDB from `nfs-truenas` to `local-path` storage — NFS produces "stale NFS file handle" errors on any TrueNAS blip, silently dropping all metrics while targets appear healthy; local disk eliminates the root cause entirely. Removed `--storage.tsdb.no-lockfile` workaround (NFS-only). Grafana and Alertmanager remain on NFS (low write frequency, not affected). → [ADR-009](docs/adr/ADR-009-prometheus-local-storage.md)
- **[MAINTENANCE]** trigger pipeline to promote system-upgrade-controller fix `1b13c52`
- **[CONFIG]** add required name and namespace env vars to system-upgrade-controller `9414dbf`
- **[CONFIG]** disable upgradeCRDs job, CRDs managed by Helm install.crds: CreateReplace `0caab65`
- **[FIX]** scope promotion pipeline pod health checks to Flux-managed namespaces only — cluster-wide check was blocking promotion on unrelated crashing pods (e.g. `system-upgrade-controller`)

- **[DEPLOY]** Promotion pipeline commissioned end-to-end; prod Grafana live at `https://grafana.kagiso.me` with trusted TLS — fixes spanned NFS `nfs-common` missing on staging node, Grafana `initChownData` NFS root squash, Loki `RetriesExceeded`, MetalLB IP pool missing on prod, Cloudflare secret missing on prod, and three CI pipeline bugs (SHA mismatch, sync timeout, missing trigger paths) → [details](docs/ops-log/2026-03-22-promotion-pipeline-and-prod-grafana.md)

- **[CONFIG]** Staging environment fixes — Flux healthCheck wrong Deployment name, Traefik IP outside staging MetalLB pool, staging/prod access pattern established → [details](docs/ops-log/2026-03-22-grafana-ingress-staging-fixes.md)

- **[FIX]** switch Velero kubectl init container from `bitnami/kubectl` to `registry.k8s.io/kubectl:v1.32.0` — Bitnami stopped publishing images to Docker Hub (now behind authentication); all pulls were failing with `not found` errors, blocking Velero CRD upgrade job on bootstrap
- **[CONFIG]** enable CRDs subchart for v1.16 compatibility `2623c83`
- **[MAINTENANCE]** encrypt grafana admin secret `0b3e3b7`
- **[MAINTENANCE]** encrypt velero minio credentials and add sops rule for minio-credentials `c2f7df9`
- **[CONFIG]** (doc)complete documentation rework. Fixed sequence, added new guides, and updated existing ones to reflect the latest changes in the platform architecture and operations. This commit also includes updates to the README and roadmap to align with the new documentation structure. `1588e6a`
- **[CONFIG]** update cert-manager HelmRelease to disable ServiceMonitor during bootstrap `83f6fd1`
- **[DEPLOY]** add ansible vault with Flux GitHub SSH credentials `219c65f`
- **[MAINTENANCE]** configure SOPS encryption rules with age public key `1138c4f`
- **[DEPLOY]** add configuration steps for RPi as Tailscale exit node fix(ansible): update Pi-hole DNS restart method and add readiness check `bb04425`
- **[DEPLOY]** add initial ansible.cfg configuration file `4d48f94`
- **[CONFIG]** update Ansible inventory instructions and add vault password file setup `2b30b27`
- **[CONFIG]** split all CRD-dependent resources into separate Kustomizations `21e566e`
- **[CONFIG]** split metallb-config into separate Kustomization to resolve CRD dry-run failure on bootstrap `ea78f6d`
- **[DEPLOY]** pre-create cert-manager namespace and Cloudflare API token secret for DNS-01 validation `a4e518d`
- **[CONFIG]** update install-platform.yml for Flux GitOps setup and enhance vault.yml.example with Cloudflare and SSH key details `26c4283`
- **[CONFIG]** update purge-k3s playbook paths and improve uninstall commands `015454e`
- **[MAINTENANCE]** configure SOPS encryption rules with age public key `e191383`
- **[CONFIG]** update SOPS installation to auto-detect latest version and support arm64 architecture `99b858d`
- **[DEPLOY]** add cloudflare_api_token secret management and update ansible configuration `5c1b261`
- **[DEPLOY]** add Pi-hole Ansible playbook and inventory rpi group `613cb4e`
- **[CONFIG]** remove Let's Encrypt, add Cloudflare Tunnel + Tailscale docs `8fe5366`
- **[CONFIG]** consolidate to Cloudflare Tunnel, remove letsencrypt-staging `bcc39cb`
- **[DEPLOY]** consolidate monitoring to k3s, decommission Docker monitoring stack `6599c0b`
- **[DEPLOY]** add ops-log, staging environment, and GitOps promotion pipeline `c2cb80c`

- **[HARDWARE]** Decision: pivot Intel NUC from bare Docker host to Proxmox VE hypervisor (docker-vm + staging-k3s VM) — pending RAM upgrade → [details](docs/ops-log/2026-03-16-pivot-nuc-to-proxmox.md)

- **[DEPLOY]** Networking platform stack: MetalLB (10.0.10.110–125) + cert-manager + Traefik v3 pinned to 10.0.10.110 → [details](docs/ops-log/2026-03-16-deploy-platform-stack.md)
- **[DEPLOY]** Initial infrastructure: 3-node k3s cluster, FluxCD v2 GitOps, SOPS/age secrets, Prometheus + Grafana + Loki monitoring stack → [details](docs/ops-log/2026-03-16-initial-infrastructure-setup.md)
