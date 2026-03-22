# 2026-03-22 — DEPLOY: Promotion Pipeline Commissioning and Prod Grafana Bring-up

**Operator:** Kagiso
**Type:** `DEPLOY`
**Components:** GitHub Actions · Flux · MetalLB · cert-manager · Grafana · Loki · NFS
**Commit:** 64c24cb
**Downtime:** None

---

## What Changed

The full staging → prod promotion pipeline was commissioned end-to-end for the first time.
This session covered: bringing up the monitoring stack on staging, fixing the pipeline itself,
and resolving all blockers that prevented Grafana from being accessible on prod via
`https://grafana.kagiso.me` with a trusted TLS certificate.

---

## Why

The staging cluster was freshly deployed and the monitoring stack had not been validated.
The promotion pipeline existed in code but had never successfully completed a full run.
Prod had no MetalLB IP pool, no Cloudflare secret, and no working TLS cert.

---

## Details

### Monitoring stack bring-up on staging

**NFS mount failure — `nfs-common` missing on staging node**
- All PVCs in `monitoring` namespace stuck `Pending`
- NFS provisioner pod stuck `ContainerCreating` with `mount: bad option; need helper program`
- Root cause: `nfs-common` not installed on the staging VM (ThinkCentre running staging-k3s)
- Fix: `sudo apt-get install -y nfs-common` on the staging node
- All PVCs bound immediately after; monitoring pods came up within minutes

**Grafana init container failure — NFS root squash**
- `kube-prometheus-stack-grafana` stuck in `Init:Error`
- `init-chown-data` container runs `chown /var/lib/grafana` which NFS root squash rejects
- Fix: added `grafana.initChownData.enabled: false` to `platform/observability/kube-prometheus-stack/helmrelease.yaml`

**Loki HelmRelease stuck in `RetriesExceeded`**
- Loki pods were running (NFS fix resolved the underlying issue) but the HelmRelease had
  exhausted its 4 install retries during the period when NFS was broken
- Fix: `flux suspend helmrelease loki-stack -n monitoring && flux resume helmrelease loki-stack -n monitoring`
- HelmRelease recovered to `Ready: True`

---

### Promotion pipeline commissioning

**Self-hosted runner installed on bran**
- GitHub Actions runner installed at `/opt/github-runner` on bran (10.0.10.10)
- Runs as a systemd service via `./svc.sh install && ./svc.sh start`
- Labels: `[self-hosted, linux, homelab]`
- Required tools pre-installed: `kubectl`, `flux`, `kubeconform`, `kustomize`
- GitHub secrets added: `STAGING_KUBECONFIG`, `PROD_KUBECONFIG`

**Pipeline fix 1 — Flux sync wait timed out (120s too short)**
- `staging-health` job timed out waiting for Flux to sync the triggering commit
- Root cause: 120s window too tight — Flux polls every 1 minute and the runner had overhead
- Fix: added `flux reconcile source git flux-system` before the wait loop to force an
  immediate pull; increased timeout to 180s

**Pipeline fix 2 — SHA mismatch due to bot commits**
- Automated workflows (Ops Log Reminder, Auto-append Changelog) push commits to `main`
  after the triggering commit, advancing HEAD
- `actions/checkout@v4` in `staging-health` was checking out the new HEAD, not the
  triggering commit — causing the SHA to never match what Flux had synced
- Fix: pinned the checkout to `ref: ${{ github.sha }}` to always use the triggering commit

**Pipeline fix 3 — `clusters/prod/**` not in trigger paths**
- Changes to `clusters/prod/infrastructure.yaml` never triggered the promotion workflow
- Only `apps/**`, `platform/**`, and `clusters/staging/**` were watched
- Fix: added `clusters/prod/**` to the `on.push.paths` list in `promote-to-prod.yml`

---

### Prod Grafana bring-up

**MetalLB had no IP pool on prod**
- `kubectl get svc traefik -n ingress` showed `EXTERNAL-IP: <pending>`
- Root cause: `platform-networking-config` Flux Kustomization (which deploys the
  `IPAddressPool` and `L2Advertisement`) only existed in `clusters/staging/infrastructure.yaml`
  — it was never added to `clusters/prod/infrastructure.yaml`
- Fix: added `platform-networking-config` Kustomization to prod infrastructure manifest
- Traefik assigned `10.0.10.110` after reconciliation

**Cloudflare API token secret missing on prod**
- `wildcard-kagiso-me` certificate stuck `Ready: False` for 50+ minutes
- cert-manager challenge controller logging: `error getting cloudflare secret: secrets "cloudflare-api-token" not found`
- Root cause: the secret is created manually post-bootstrap and was only documented for
  staging — the prod bootstrap section in Guide 04 made no mention of this step
- Fix: `kubectl create secret generic cloudflare-api-token --namespace cert-manager --from-literal=api-token=<token>`
- Guide 04 updated to include this step explicitly after prod bootstrap
- After deleting the stale challenge, cert-manager re-presented the DNS-01 challenge,
  Cloudflare API created the TXT record, and both challenges became `valid`

---

## Outcome

- [x] Full monitoring stack running on staging (Prometheus, Grafana, Alertmanager, Loki, Promtail)
- [x] Promotion pipeline completes end-to-end (validate → staging-health → promote → prod-health)
- [x] `main` → `prod` promotion is fully automated and gated on staging health
- [x] Traefik on prod assigned `10.0.10.110` via MetalLB
- [x] Wildcard cert `*.kagiso.me` issued by Let's Encrypt prod (`READY: True`)
- [x] Grafana accessible at `https://grafana.kagiso.me` with trusted TLS — no browser warnings

---

## Related

- `platform/observability/kube-prometheus-stack/helmrelease.yaml` — `initChownData` fix
- `clusters/prod/infrastructure.yaml` — added `platform-networking-config` Kustomization
- `.github/workflows/promote-to-prod.yml` — SHA pinning, flux reconcile, trigger paths
- `docs/guides/04-Flux-GitOps.md` — added Cloudflare secret step for prod bootstrap
- `docs/adr/ADR-007-self-hosted-runners.md` — self-hosted runner rationale and setup
- `docs/guides/00.5-Infrastructure-Prerequisites.md` — runner prerequisite reference
