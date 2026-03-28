
# ADR-007 — Self-Hosted GitHub Actions Runners

**Status:** Accepted
**Date:** 2026-03-19
**Deciders:** Platform team

---

## Context

The CI/CD pipeline requires network access to the homelab's internal cluster API server
(`10.0.10.11` for prod) to perform post-merge health checks after every push to `main`.
GitHub-hosted runners run in GitHub's cloud infrastructure and cannot reach RFC-1918
addresses on the homelab LAN.

Two options were evaluated to bridge this gap:

1. **Tailscale ephemeral nodes** — connect each GitHub-hosted runner to the homelab network
   via `tailscale/github-action` before running `kubectl` commands.
2. **Self-hosted runner on bran** — install the GitHub Actions runner agent on the Raspberry
   Pi (`bran`, 10.0.10.10), which already has direct LAN access to all cluster nodes.

## Decision

**Self-hosted runner on bran (10.0.10.10) is used for all cluster-touching CI jobs.**

Static analysis jobs (kubeconform, kustomize build, pluto, flux-local diff) run on
`ubuntu-latest` GitHub-hosted runners — they require no cluster access and benefit from
GitHub's hosted infrastructure being independent of homelab availability.

The post-merge health check job requires direct cluster access and runs on the self-hosted
runner with label `[self-hosted, linux, homelab]`.

## Rationale

| Criterion | Tailscale ephemeral | Self-hosted runner |
|-----------|--------------------|--------------------|
| Cluster network access | Via VPN (added latency, handshake per job) | Direct LAN (native speed) |
| Tooling versions | Downloaded fresh each run | Pre-installed, consistent |
| CI job speed | ~90s to install tools + VPN handshake | ~10s (tools already present) |
| External service dependency | Requires Tailscale to be operational | None beyond GitHub |
| Secret management | `TAILSCALE_AUTH_KEY` + kubeconfig with Tailscale IPs | Kubeconfig with internal IPs only |
| Runner maintenance | Zero (GitHub managed) | Minimal (systemd service + auto-update) |
| Architectural lock-in | Tailscale required for CI to function | No third-party dependency |

The Tailscale approach creates a hard dependency: if Tailscale's auth service is unavailable,
or if the auth key expires, or if Tailscale's GitHub Action API changes, CI breaks entirely.
This couples cluster operations to a third-party SaaS product.

The self-hosted runner eliminates this coupling. `bran` is already the homelab automation
host (Ansible, monitoring), is always on, and has LAN-level access to the prod cluster.
The runner agent auto-updates itself when GitHub signals a new minimum version is required —
no manual intervention needed in normal operation.

## Runner Role in the CI Pipeline

The runner participates in two distinct phases of the pipeline:

**PR phase (static analysis — GitHub-hosted runners):**
- `kubeconform` — validates all YAML manifests against Kubernetes schemas
- `kustomize build` — confirms overlays render without errors
- `pluto` — detects use of deprecated or removed Kubernetes APIs
- `flux-local diff` — renders a diff of what changes will be applied to the cluster and posts it as a PR comment

**Post-merge phase (cluster health check — self-hosted runner):**
- Triggers a Flux source reconciliation to pull the merged commit
- Waits for all Flux kustomizations to report `Ready`
- Confirms Traefik responds at its MetalLB VIP
- Fails the workflow (and fires a GitHub Actions notification) if the cluster is unhealthy after the merge

This split ensures that manifest validation never depends on homelab availability, while the health check that verifies the live cluster always has direct LAN access.

## Consequences

**Positive:**
- No Tailscale dependency in the CI pipeline
- Faster health check jobs (pre-installed kubectl, flux CLI; no VPN handshake)
- Kubeconfig secret uses plain internal IP (`10.0.10.11`) — simpler to generate and rotate
- CI pipeline is fully independent of any third-party network service
- 100% of manifests are validated before they reach the cluster

**Negative:**
- If `bran` is offline, the post-merge health check queues indefinitely rather than failing fast
- The runner agent systemd service must be configured to start on boot
- Pre-installed tools (kubectl, flux CLI, kubeconform, kustomize, pluto) must be present and current on bran

**Learned in practice:**
- Pod health checks must be scoped to Flux-managed namespaces only (`flux-system`, `ingress`,
  `cert-manager`, `monitoring`, `storage`, `velero`, `metallb-system`). A cluster-wide `-A`
  check causes the health job to block on unrelated crashing pods (e.g. `system-upgrade-controller`)
  that have nothing to do with the changes being merged.

## Runner Setup

Install the GitHub Actions runner on `bran` (10.0.10.10):

```bash
# 1. Create a dedicated user (optional but recommended)
sudo useradd -m -s /bin/bash github-runner

# 2. Download the runner (check github.com/actions/runner/releases for latest)
RUNNER_VERSION="2.321.0"
mkdir -p /opt/github-runner && cd /opt/github-runner
curl -sL "https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/actions-runner-linux-arm64-${RUNNER_VERSION}.tar.gz" \
  | tar -xz

# 3. Get a registration token:
#    GitHub → Repository → Settings → Actions → Runners → New self-hosted runner
#    Set architecture to arm64. Copy the token from the ./config.sh command shown
#    on that page (valid for 1 hour, single use).
./config.sh \
  --url https://github.com/Kagiso-me/homelab-infrastructure \
  --token <TOKEN_FROM_GITHUB> \
  --labels homelab \
  --name bran \
  --unattended

# 4. Install and start as a systemd service (NOT ./run.sh — that only runs in the foreground)
sudo ./svc.sh install
sudo ./svc.sh start

# 5. Verify
sudo ./svc.sh status
```

Pre-install required tools on `bran`:

```bash
# kubectl (ARM64)
curl -sL "https://dl.k8s.io/release/$(curl -sL https://dl.k8s.io/release/stable.txt)/bin/linux/arm64/kubectl" \
  -o /usr/local/bin/kubectl && chmod +x /usr/local/bin/kubectl

# flux CLI (ARM64)
curl -s https://fluxcd.io/install.sh | FLUX_VERSION=2.4.0 bash

# kubeconform (ARM64)
KUBECONFORM_VERSION="v0.6.7"
curl -sSL "https://github.com/yannh/kubeconform/releases/download/${KUBECONFORM_VERSION}/kubeconform-linux-arm64.tar.gz" \
  | tar -xz -C /usr/local/bin kubeconform

# kustomize (ARM64)
curl -sSL https://raw.githubusercontent.com/kubernetes-sigs/kustomize/master/hack/install_kustomize.sh | bash
sudo mv kustomize /usr/local/bin/

# pluto (ARM64) — deprecated API detection
PLUTO_VERSION="v5.19.4"
curl -sSL "https://github.com/FairwindsOps/pluto/releases/download/${PLUTO_VERSION}/pluto_${PLUTO_VERSION#v}_linux_arm64.tar.gz" \
  | tar -xz -C /usr/local/bin pluto
```

## Required Secrets

Add these to the GitHub repository under **Settings → Secrets and variables → Actions**:

| Secret | Value |
|--------|-------|
| `KUBECONFIG` | Contents of `/etc/rancher/k3s/k3s.yaml` on `tywin` (server stays as `10.0.10.11:6443`) |

No Tailscale auth key is required. No staging kubeconfig is required — the staging cluster has been decommissioned (see ADR-006, ADR-012).
