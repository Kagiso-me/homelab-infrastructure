# Runbook — Add a GitHub Actions Self-Hosted Runner

## When to use this

- Adding a runner for a new repository
- Migrating an existing runner to a new node (e.g. varys → bran)
- Re-registering a runner after it was accidentally deregistered

## Context

Each runner must live in its own directory. See ADR-007 for the full rationale and the
current directory convention. Never run `config.sh` inside a directory that already has
a registered runner — it will overwrite the existing registration.

---

## Steps

### 1. Create a directory for the new runner

```bash
# Use a descriptive name — repo name is a good convention
mkdir ~/actions-runner-<repo-name>
cd ~/actions-runner-<repo-name>
```

### 2. Download the runner agent

Get the latest version and the exact download URL from:
**GitHub → target repo → Settings → Actions → Runners → New self-hosted runner → Linux**

The page shows the exact `curl` command with the current version. Copy and run it:

```bash
curl -o actions-runner-linux-x64-<VERSION>.tar.gz -L \
  https://github.com/actions/runner/releases/download/v<VERSION>/actions-runner-linux-x64-<VERSION>.tar.gz
tar xzf ./actions-runner-linux-x64-<VERSION>.tar.gz
```

> Note: varys is x64 (Intel NUC). bran (RPi) is arm64 — use `actions-runner-linux-arm64` instead.

### 3. Get a registration token

**GitHub → target repo → Settings → Actions → Runners → New self-hosted runner**

Copy the `--token` value from the `./config.sh` command shown on that page.
Tokens are single-use and expire after 1 hour.

### 4. Register the runner

```bash
./config.sh \
  --url https://github.com/Kagiso-me/<repo-name> \
  --token <TOKEN_FROM_GITHUB> \
  --name <node-name>-<short-repo> \
  --labels self-hosted,linux,homelab \
  --unattended
```

Example for the site repo on varys:
```bash
./config.sh \
  --url https://github.com/Kagiso-me/Kagiso-me.github.io \
  --token <TOKEN> \
  --name varys-site \
  --labels self-hosted,linux,homelab \
  --unattended
```

### 5. Install and start as a systemd service

```bash
# Pass your username so the service runs as you (not root)
./svc.sh install kagiso
./svc.sh start
```

The systemd service name will be based on the runner name, e.g. `actions-runner.varys-site.service`.

### 6. Verify

```bash
sudo systemctl status actions-runner.varys-site.service
```

In GitHub: **Settings → Actions → Runners** — the runner should appear as **Idle**.

---

## Removing a runner

```bash
cd ~/actions-runner-<repo-name>
./svc.sh stop
./svc.sh uninstall

# Get a removal token from: GitHub → repo → Settings → Actions → Runners → runner → Remove
./config.sh remove --token <REMOVE_TOKEN>

# Clean up the directory
cd ~
rm -rf ~/actions-runner-<repo-name>
```

---

## Current runner locations

All runners live on `bran` (10.0.10.9, aarch64). Provisioned via:
```bash
ansible-playbook -i ansible/inventory/homelab.yml \
  ansible/playbooks/services/provision-bran-runners.yml \
  -e "token_site=<TOKEN> token_k3s=<TOKEN> token_docker=<TOKEN>"
```

| Runner | Directory | Label | Workflow |
|--------|-----------|-------|----------|
| Site data pipeline | `~/actions-runner-site/` | `bran-site` | `fetch-live-data.yml` |
| k3s health check + flux diff | `~/actions-runner-k3s/` | `bran-k3s` | `validate.yml` |
| Docker deploy | `~/actions-runner-docker/` | `bran-docker` | `docker-deploy.yml` |

---

## Required secrets per repository

| Repository | Secret | Value |
|------------|--------|-------|
| `homelab-infrastructure` | `KUBECONFIG` | Contents of `/etc/rancher/k3s/k3s.yaml` on tywin |
| `Kagiso-me.github.io` | `SITE_DEPLOY_TOKEN` | Fine-grained PAT, `Contents: read+write` on `Kagiso-me.github.io` only |
| `Kagiso-me.github.io` | `SSH_PRIVATE_KEY` | Private key for SSH access to varys from the runner |
