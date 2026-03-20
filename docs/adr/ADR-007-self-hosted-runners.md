
# ADR-005 — Self-Hosted GitHub Actions Runners

**Status:** Accepted
**Date:** 2026-03-19
**Deciders:** Platform team

---

## Context

The CI/CD pipeline (`promote-to-prod.yml`) requires network access to the homelab's internal
cluster API servers (`10.0.10.11` for prod, `10.0.10.31` for staging) to perform health checks
after every `main` branch push. GitHub-hosted runners run in GitHub's cloud infrastructure
and cannot reach RFC-1918 addresses on the homelab LAN.

Two options were evaluated to bridge this gap:

1. **Tailscale ephemeral nodes** — connect each GitHub-hosted runner to the homelab network
   via `tailscale/github-action` before running `kubectl` commands.
2. **Self-hosted runner on bran** — install the GitHub Actions runner agent on the Raspberry
   Pi (`bran`, 10.0.10.10), which already has direct LAN access to all cluster nodes.

## Decision

**Self-hosted runner on bran (10.0.10.10) is used for all cluster-touching CI jobs.**

The `validate` job (kubeconform + kustomize build) continues to run on `ubuntu-latest` —
it requires no cluster access and benefits from GitHub's hosted infrastructure being
independent of homelab availability.

Jobs that require cluster access use the runner label `[self-hosted, linux, homelab]`.

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
host (Ansible, monitoring), is always on, and has LAN-level access to both clusters.
The runner agent auto-updates itself when GitHub signals a new minimum version is required —
no manual intervention needed in normal operation.

## Consequences

**Positive:**
- No Tailscale dependency in the CI pipeline
- Faster health check jobs (pre-installed kubectl, flux CLI; no VPN handshake)
- Kubeconfig secrets use plain internal IPs (`10.0.10.11`, `10.0.10.31`) — simpler to generate
- CI pipeline is fully independent of any third-party network service

**Negative:**
- If `bran` is offline, health check jobs queue indefinitely rather than failing fast
- The runner agent systemd service must be configured to start on boot
- Pre-installed tools (kubectl, flux CLI, kubeconform, kustomize) must be present on bran

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

# 3. Configure — get the token from GitHub:
#    Repository → Settings → Actions → Runners → New self-hosted runner
./config.sh \
  --url https://github.com/Kagiso-me/homelab-infrastructure \
  --token <TOKEN_FROM_GITHUB> \
  --labels homelab \
  --name bran \
  --unattended

# 4. Install and start as a systemd service
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
```

## Required Secrets

Add these to the GitHub repository under **Settings → Secrets and variables → Actions**:

| Secret | Value |
|--------|-------|
| `STAGING_KUBECONFIG` | Contents of `/etc/rancher/k3s/k3s.yaml` on the staging VM (server stays as `10.0.10.31:6443`) |
| `PROD_KUBECONFIG` | Contents of `/etc/rancher/k3s/k3s.yaml` on `tywin` (server stays as `10.0.10.11:6443`) |

No Tailscale auth key is required.
