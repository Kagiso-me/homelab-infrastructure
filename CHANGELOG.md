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

## 2026-04
- **[MAINTENANCE]** upgrade k3s to v1.34.6, remove ned from inventory `e8c3f03`
- **[CONFIG]** match OIDC login identity by email instead of username `966547b`
- **[DEPLOY]** apply secure-headers, compress, and crowdsec-bouncer middlewares globally `a6fc69c`
- **[DEPLOY]** wire Resend SMTP into Nextcloud, Vaultwarden, and Authentik `43b9cee`
- **[CONFIG]** correct HTTP→HTTPS redirect entrypoint key for traefik-internal `4a64840`
- **[CONFIG]** use source.toolkit.fluxcd.io/v1 for HelmRepository `588f635`
- **[DEPLOY]** add Seerr and cluster maintenance playbooks `efb4a1b`
- **[MAINTENANCE]** update prom/node-exporter docker tag to v1.11.1 (#76) `dc7d0fe`
- **[CONFIG]** standardise deploy path to /srv/docker/compose across all layers `0880230`
- **[CONFIG]** remove unused assets-path causing startup error `8d18e17`
- **[MAINTENANCE]** update helm release kube-prometheus-stack to v83.4.0 `aab945e`
- **[CONFIG]** use /srv/docker/compose/.env instead of stacks/.env `6a5bdd8`
- **[CONFIG]** rollback to v28.3.0 — v39 schema incompatible with websecure-int `dbd1908`
- **[CONFIG]** replace removed community.general.yaml callback with result_format=yaml `6319675`
- **[MAINTENANCE]** removed freshRSS and overseer from docker. These will be re-deployed in the k3s cluster `dc312f7`
- **[CONFIG]** allow SSH from bran on k3s nodes `2ff6abe`
- **[CONFIG]** copy vault_pass to bran in provision playbook `437c72b`
- **[CONFIG]** symlink ansible bins to /usr/local/bin on bran `7316402`
- **[DEPLOY]** migrate all CI runners from varys to bran `9cf344f`
- **[MAINTENANCE]** update helm release crowdsec to >=0.9.12 (#15) `6c5b333`
- **[DEPLOY]** add node-exporter to all non-k3s hosts `7c89416`
- **[MAINTENANCE]** rename hodor → bran (Three-Eyed Raven — sees everything) `9795335`
- **[MAINTENANCE]** establish GoT naming convention across all nodes and docs `ebf9603`
- **[DEPLOY]** add *.local.kagiso.me wildcard DNS for internal Traefik `b9410ba`
- **[MAINTENANCE]** update helm release cert-manager to v1.16.5 (#14) `8ae1ea6`
- **[CONFIG]** resolve automerge rule conflicts and simplify packageRules `0c6a182`
- **[DEPLOY]** pin image tags and configure Renovate for compose files `dde2b50`
- **[MAINTENANCE]** migrate Renovate config (#11) `2ed9e73`
- **[DEPLOY]** block admin paths on external ingress for Vaultwarden and Authentik `2a9b467`
- **[CONFIG]** shorten entrypoint name to websecure-int `4e3033d`
- **[DEPLOY]** wire internal IngressRoutes into kustomizations `6220128`
- **[DEPLOY]** add traefik-internal for LAN-only ingress tier `76ea486`
- **[CONFIG]** increase replicas to 3 to match 3-node cluster `c234666`
- **[CONFIG]** quote database port to prevent float encoding in DB URI `a1f652f`
- **[CONFIG]** switch chart source to guerzon HelmRepository `0fc8d9b`
- **[DEPLOY]** deploy Vaultwarden + roadmap cleanup `d4f0b05`
- **[CONFIG]** raise memory limit to 2Gi to prevent OOMKill `5f4af3f`
- **[CONFIG]** extend liveness/startup probes for NFS WAL recovery `44d1fcc`
- **[CONFIG]** disable k3s-incompatible PrometheusRule groups properly `8de02bb`
- **[DEPLOY]** move freshrss to media-stack `deab6b4`
- **[DEPLOY]** add freshrss to platform-stack `008c5c7`
- **[DEPLOY]** add platform-stack with glance and uptime-kuma `70ddc88`
- **[DEPLOY]** add NFS PostgreSQL performance alerts `a31b26a`
- **[CONFIG]** fix docker ps format string causing Ansible Jinja2 template error `e3e1485`
- **[DEPLOY]** add glance dashboard on port 8800 `f381373`
- **[DEPLOY]** add nfs-databases StorageClass for database workloads `312fbd8`
- **[CONFIG]** set fsGroup for NFS mount ownership `456e7a4`
- **[CONFIG]** migrate PostgreSQL and Prometheus to NFS, pin Redis to tywin `01b7072`
- **[CONFIG]** update monitoring-stack cadvisor port and disable_metrics flag `c6fefac`
- **[CONFIG]** update cadvisor port to 9338 on Docker host `1f03bf5`
- **[CONFIG]** disable k3s-incompatible default rules `bedd8a3`
- **[DEPLOY]** re-enable AlertmanagerConfig and secret for in-cluster alertmanager `b8493b9`
- **[CONFIG]** simplify inline config to valid null receiver `bb6799e`
- **[CONFIG]** disable occ-init job (needs rework for official chart) `04aea03`
- **[CONFIG]** fix occ-init job for official chart (not bitnami) `2d76ef7`
- **[CONFIG]** fix IngressRoute service name from n8n-main to n8n `87098f7`
- **[CONFIG]** add init container to wait for PostgreSQL before startup `7ace908`
- **[CONFIG]** override dnsConfig to avoid stale node search domains `4c8a479`
- **[CONFIG]** pin to tywin node to avoid DNS failures on tyrion `33ea0a3`
- **[CONFIG]** disable postgres metrics sidecar (PG17 incompatible) `f30d336`
- **[CONFIG]** use valuesFrom for redis password instead of valueFrom `ffdb0b2`
- **[CONFIG]** remove memory limit and increase request for pgvector `2a3ad92`
- **[CONFIG]** switch postgres to pgvector image for Immich support `4e4e779`
- **[CONFIG]** move env vars under server.controllers path `d7ac8c5`
- **[CONFIG]** use correct timezone key and chart schema `fb19ece`
- **[CONFIG]** fix env var structure for bjw-s common chart `09e20a6`
- **[CONFIG]** fix schema error and postgres hostname `9376ff9`
- **[CONFIG]** re-encrypt app secrets with cluster age key `7738e0d`
- **[CONFIG]** add allow-from-ingress to crowdsec namespace `df55956`
- **[CONFIG]** add allow-from-ingress NetworkPolicy to monitoring namespace `3f9e01e`
- **[CONFIG]** correct admin secret name to grafana-admin `6d5b682`
- **[CONFIG]** disable initChownData — NFS blocks chown from non-root containers `84fe40b`
- **[DEPLOY]** enable Grafana and Alertmanager in-cluster with Discord (#9) `eb0d10b`
- **[DEPLOY]** switch to official upstream chart (#8) `852fa2d`
- **[CONFIG]** use port 9000 in IngressRoute (#7) `db75a07`

- **[CONFIG]** correct postgresql hostname to postgresql-primary (#6) `14bde9b`

## 2026-03
- **[CONFIG]** relocate downloads path under /srv/docker/downloads `122a6ba`
- **[CONFIG]** rewrite n8n helmrelease using correct chart schema `fa684cb`
- **[CONFIG]** fix n8n extraEnvVars format — map not array `eb3eef3`
- **[CONFIG]** fix n8n helmrelease values schema `49c387e`
- **[DEPLOY]** encrypt Immich and n8n secrets `4824ec6`
- **[DEPLOY]** add Immich and n8n deployments `8ebede7`
- **[CONFIG]** fix node-deep-dive variable and queries to use instance labels `a2a264a`
- **[CONFIG]** switch digest to python:3.12-alpine `799866f`
- **[DEPLOY]** add full monitoring stack overhaul `d3a8e13`
- **[MAINTENANCE]** encrypt daily-digest Discord webhook secret `9de947d`
- **[DEPLOY]** add daily homelab digest CronJob `0d9a041`
- **[DEPLOY]** add Discord webhook URLs to secret `b5d1c2b`
- **[DEPLOY]** add CoreDNS split-horizon for kagiso.me `d98585c`
- **[CONFIG]** enable OIDC user auto-registration `9f44645`
- **[CONFIG]** bypass Cloudflare for OIDC discovery via hostAlias `513fa56`
- **[DEPLOY]** add OIDC client credentials to secret `d20252b`
- **[DEPLOY]** add Authentik OIDC login via oidc_login app `4a55034`
- **[CONFIG]** pin media-net network name to prevent compose prefix `d429c22`
- **[CONFIG]** correct redis password in secret `cb40883`
- **[CONFIG]** run as uid 1000 to match NFS mapall owner `b4b67c5`
- **[CONFIG]** remove invalid capabilities from pod securityContext `45cabe9`
- **[CONFIG]** run as www-data with NET_BIND_SERVICE to avoid NFS chown failures `47ce1c4`
- **[DEPLOY]** overhaul Grafana dashboards and add Backblaze B2 monitoring `a17479b`
- **[CONFIG]** increase install timeout and probe delays for first-run DB setup `fda90d0`
- **[CONFIG]** disable chart defaultConfigs for redis and reverse-proxy to prevent duplicate YAML keys `b674304`
- **[CONFIG]** use cloud.kagiso.me hostname `24375b8`
- **[CONFIG]** rename config keys to avoid collision with chart defaults `ddc3afb`
- **[DEPLOY]** add encrypted Nextcloud secret `7cdd54d`
- **[DEPLOY]** add Nextcloud deployment `b5f450b`
- **[MAINTENANCE]** add Resend SMTP API key to secret `e6dca39`
- **[DEPLOY]** configure Resend SMTP for transactional email `c8ef514`
- **[CONFIG]** use job labels for external node queries in overview dashboard `61ad074`
- **[DEPLOY]** add CrowdSec security dashboard with geo threat map `7098963`
- **[CONFIG]** remove http:// scheme from crowdsec_agent_host — bouncer prepends it `9e74e5f`
- **[CONFIG]** correct bouncer service name and port in ForwardAuth middleware `e5baedf`
- **[DEPLOY]** add comprehensive homelab overview Grafana dashboard `16537a1`
- **[CONFIG]** use file source for acquisitions and snake_case bouncer values `bef2ca4`
- **[CONFIG]** correct acquisitions key and bouncer API key value path `679cce4`
- **[CONFIG]** use HelmRepository apiVersion v1 for cluster compatibility `116021b`
- **[MAINTENANCE]** re-encrypt CrowdSec bouncer API key `738832f`
- **[MAINTENANCE]** encrypt CrowdSec bouncer API key `6293d2f`
- **[MAINTENANCE]** encrypt CrowdSec bouncer API key `bd34cab`
- **[DEPLOY]** deploy CrowdSec with Traefik ForwardAuth bouncer `6b12cb5`
- **[CONFIG]** switch to shared Redis instance `255e766`
- **[DEPLOY]** add app-health rules and Authentik dashboard `f0a8c98`
- **[CONFIG]** switch to shared PostgreSQL, keep bundled Redis `88f1bf5`
- **[MAINTENANCE]** encrypt secret `28bdc3d`
- **[DEPLOY]** add Authentik SSO identity provider `4f279f5`
- **[DEPLOY]** add 6-hourly databases backup schedule `250cba2`
- **[DEPLOY]** add Velero metrics section to backup overview dashboard `6753f7d`
- **[CONFIG]** correct node-agent pod volume path for this k3s installation `67f9fd1`
- **[CONFIG]** track .env.example so it's available after clone `08a7f29`
- **[CONFIG]** use deployNodeAgent: true to enable node-agent DaemonSet `12bc330`
- **[CONFIG]** add control-plane toleration to node-agent DaemonSet `7383ee7`
- **[CONFIG]** disable VolumeSnapshotLocation and enable defaultVolumesToFsBackup `8832401`
- **[CONFIG]** remove http:// from etcd S3 endpoint — k3s expects host:port only `4d88d4a`
- **[CONFIG]** simplify etcd snapshot command — S3 flags already in config.yaml `cb6ccb0`
- **[CONFIG]** correct vault path to ../vars/vault.yml `7334af3`
- **[CONFIG]** correct vault path in configure-etcd-snapshots playbook `6f070ce`
- **[DEPLOY]** add latency and resource panels to database dashboards `35c5178`
- **[CONFIG]** correct datasource variable for Grafana dashboard templating `6da24c3`
- **[DEPLOY]** metrics, dashboards, backup, and etcd snapshot offloading `2434907`
- **[CONFIG]** allow bitnamilegacy image for Redis `4eb0f10`
- **[CONFIG]** use bitnamilegacy image registry `c54710f`
- **[CONFIG]** switch Bitnami HelmRepository back to HTTPS `521f9c4`
- **[CONFIG]** switch Bitnami HelmRepository to OCI `389277b`
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
