
# 04 — GitOps Control Plane (FluxCD)
## Turning Git Into the Cluster API

**Author:** Kagiso Tjeane
**Difficulty:** ⭐⭐⭐⭐⭐⭐⭐⭐☆☆ (8/10)
**Guide:** 04 of 13

> Up to this point the cluster has been built using traditional infrastructure automation.
> Nodes were prepared with Ansible, Kubernetes was installed, and the networking platform
> (MetalLB + Traefik + DNS + TLS) now exposes services to the network.
>
> The next step is a major architectural shift:
>
> **Git becomes the control plane for the platform.**

In this phase we install **FluxCD**, a GitOps controller that continuously reconciles
the state of the Kubernetes cluster with the contents of a Git repository.

From this point forward:

```
Git commit → Flux reconciliation → Cluster state updated
```

No more manual `kubectl apply` operations for platform services or applications.

---

# What GitOps Means

Traditional Kubernetes operations often look like this:

```
Engineer → kubectl apply -f deployment.yaml
```

Over time this causes problems:

• configuration drift
• undocumented changes
• difficult rollbacks
• inconsistent environments

GitOps replaces manual operations with a **declarative workflow**.

```mermaid
graph LR
    Dev["Developer"] -->|git commit + push| Git["GitHub<br/>homelab-infrastructure"]
    Git -->|poll every 1m| Flux["Flux Source Controller"]
    Flux --> Kustomize["Kustomize Controller<br/>applies manifests"]
    Flux --> Helm["Helm Controller<br/>manages HelmReleases"]
    Kustomize --> K8s["Kubernetes Cluster"]
    Helm --> K8s
    style Git fill:#24292e,color:#fff
    style K8s fill:#326ce5,color:#fff
```

The cluster always converges toward the desired state defined in Git.

---

# Why Flux Was Chosen

Flux is one of the two dominant GitOps tools in Kubernetes (the other being ArgoCD).

Flux was selected because it is:

• lightweight
• Kubernetes-native
• fully declarative
• CNCF graduated
• widely used in platform engineering environments

Flux works by deploying several controllers inside the cluster.

---

# Flux Architecture

Flux consists of several cooperating controllers.

```mermaid
graph TD
    Repo["Git Repository<br/>github.com/Kagiso-me/homelab-infrastructure"]
    SC["Source Controller<br/>pulls Git every 1m"]
    KC["Kustomize Controller<br/>applies raw manifests + Kustomizations"]
    HC["Helm Controller<br/>installs/upgrades HelmReleases"]
    NC["Notification Controller<br/>sends alerts + events"]
    Cluster["Kubernetes Cluster"]

    Repo --> SC
    SC --> KC
    SC --> HC
    SC --> NC
    KC --> Cluster
    HC --> Cluster
```

Each controller performs a specific function.

| Controller | Responsibility |
|-----------|---------------|
source-controller | pulls Git repositories |
kustomize-controller | applies manifests |
helm-controller | manages Helm releases |
notification-controller | handles alerts and events |

---

# Repository Structure

This repository uses a two-environment layout. Every change lands in `staging` first and
is automatically promoted to `production` after validation.

```
homelab-infrastructure/
├── clusters/
│   ├── prod/
│   │   └── flux-system/     ← prod Flux sync (watches prod branch)
│   └── staging/
│       └── flux-system/     ← staging Flux sync (watches main branch)
├── platform/                ← shared platform services (MetalLB, Traefik, cert-manager)
└── apps/
    ├── base/                ← shared app manifests
    ├── prod/                ← prod overlay (full resources, production certs)
    └── staging/             ← staging overlay (reduced resources, staging certs)
```

| Directory | Purpose |
|----------|---------|
`clusters/prod/flux-system` | Prod Flux sync — watches the `prod` branch |
`clusters/staging/flux-system` | Staging Flux sync — watches the `main` branch |
`platform/` | Shared platform services — same manifests for both environments |
`apps/base/` | Shared application manifests |
`apps/prod/` | Production Kustomize overlay |
`apps/staging/` | Staging Kustomize overlay |

## Promotion Model

```
git push → main
    ↓
GitHub Actions: kubeconform + kustomize build
    ↓
Flux staging reconciles (watches main)
    ↓
GitHub Actions: staging health checks
    ↓
GitHub Actions: auto-merge main → prod branch
    ↓
Flux prod reconciles (watches prod branch)
```

Changes never reach production without passing through staging first.
The promotion is fully automated — no manual merge required.

Flux continuously reconciles the manifests stored here.

---

# Bootstrapping Flux

Flux is installed by **bootstrapping** the cluster to a Git repository.

This operation performs three actions:

1. installs Flux controllers in the cluster
2. commits Flux manifests into Git
3. connects the cluster to the repository

Once complete the cluster continuously monitors Git for changes.

> **This is a one-time operation per repository.** After the first bootstrap, the generated
> manifests live in `clusters/prod/flux-system/`. On every subsequent cluster rebuild, the
> `install-platform.yml` Ansible playbook re-applies those committed manifests and recreates
> the SSH secret from vault — no manual `flux bootstrap` call needed.

---

# Generate a Deploy Key

Flux authenticates to Git using SSH.

Create a key **on the Raspberry Pi**:

```bash
ssh-keygen -t ed25519 -f ~/.ssh/flux_deploy_key -C "flux@cluster"
```

This produces:

```
~/.ssh/flux_deploy_key        ← private key — keep this safe
~/.ssh/flux_deploy_key.pub    ← public key — added to GitHub
```

Add the public key to the Git repository as a **Deploy Key** with write access:

```
GitHub → homelab-infrastructure → Settings → Deploy keys → Add deploy key
Title: flux@prod-cluster
Key: <contents of ~/.ssh/flux_deploy_key.pub>
Allow write access: ✓
```

---

# Installing the Flux CLI

Install the CLI tool:

```bash
curl -s https://fluxcd.io/install.sh | sudo bash
```

Verify installation:

```bash
flux --version
```

---

# age Key Setup

Flux decrypts SOPS-encrypted secrets using an age private key stored in the cluster.
This key must exist **before** bootstrap — if Flux reconciles an encrypted secret without
it, reconciliation fails immediately.

This is a one-time setup. The same key is used for all future secret encryption in this repository.

## Step 1 — Install age and SOPS

Both tools are needed: `age` for key management, `sops` for encrypting/decrypting secret files.
Installing them here means they are available when the first encrypted secret is created in Guide 08.

```bash
# Install age
sudo apt install -y age

# Install SOPS (auto-detects latest version; uses arm64 for bran which is aarch64)
SOPS_VERSION=$(curl -s https://api.github.com/repos/getsops/sops/releases/latest | grep tag_name | cut -d'"' -f4)
sudo curl -Lo /usr/local/bin/sops "https://github.com/getsops/sops/releases/download/${SOPS_VERSION}/sops-${SOPS_VERSION}.linux.arm64"
sudo chmod +x /usr/local/bin/sops
```

Verify:

```bash
age --version
sops --version
```

## Step 2 — Generate the Key Pair

```bash
age-keygen -o ~/age.key
```

Output:

```
Public key: age1xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
```

**Copy the public key from the output above** — you will need it in the next step.

**Back up the private key now.** If this key is lost, every SOPS-encrypted secret in the
repository becomes unreadable — there is no recovery path.

Print the key content and save it to your password manager immediately:

```bash
cat ~/age.key
```

The output looks like this:

```
# created: 2026-03-18T00:00:00+02:00
# public key: age1xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
AGE-SECRET-KEY-1XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
```

Save the **entire output** (all three lines) as a secure note in your password manager
(e.g., Bitwarden, 1Password). The `AGE-SECRET-KEY-1...` line is the private key — treat it
like a master password.

> The RPi automated backup (when configured) will also protect `~/age.key` as part of the
> RPi config backup. Until that backup is running, the password manager entry is your only
> recovery option.

## Step 3 — Update .sops.yaml with the Public Key

The `.sops.yaml` file in the repository root tells SOPS which key to use when encrypting files.
Replace the placeholder with the public key printed above:

```bash
# View the current .sops.yaml
cat .sops.yaml
```

Edit `.sops.yaml` and replace every occurrence of `age1REPLACEME_WITH_YOUR_ACTUAL_AGE_PUBLIC_KEY`
with your actual public key:

```yaml
# .sops.yaml — encryption rules for this repository
creation_rules:
  - path_regex: platform/.*secret.*\.yaml$
    age: age1xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx   # ← your actual key

  - path_regex: apps/.*secret.*\.yaml$
    age: age1xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx

  - path_regex: clusters/.*secret.*\.yaml$
    age: age1xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx

  - path_regex: .*/secrets/.*\.yaml$
    age: age1xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
```

Commit this change:

```bash
git add .sops.yaml
git commit -m "chore: configure SOPS encryption rules with age public key"
git push
```

## Step 4 — Store the Key in the Cluster

```bash
kubectl create namespace flux-system || true
kubectl create secret generic sops-age \
  --namespace=flux-system \
  --from-file=age.agekey=$HOME/age.key
```

Verify:

```bash
kubectl get secret sops-age -n flux-system
```

---

# First-Time Bootstrap (One-Time Per Repository)

> **Both prod and staging clusters have already been bootstrapped.**
> These steps are preserved here for reference if the repository ever needs to be re-bootstrapped
> (e.g., changing the branch, path, or rotating the deploy key).
>
> For routine cluster rebuilds — reinstalling k3s on the same repo — use the
> **[Ansible playbook method](#installing-on-a-rebuilt-cluster-ansible)** instead.

## Step 1 — Complete age Key Setup

Ensure Steps 1–4 above are complete: age and sops installed, `.sops.yaml` updated and
committed, `sops-age` Secret present in `flux-system`.

## Step 2 — Bootstrap the Cluster

With the secret in place, bootstrap **prod** first (ThinkCentre cluster):

```bash
# On the Raspberry Pi (10.0.10.10)
flux bootstrap git \
  --url=ssh://git@github.com/Kagiso-me/homelab-infrastructure.git \
  --branch=prod \
  --path=clusters/prod \
  --private-key-file=$HOME/.ssh/flux_deploy_key
```

Bootstrap **staging** (single-node k3s on Docker NUC):

```bash
flux bootstrap git \
  --url=ssh://git@github.com/Kagiso-me/homelab-infrastructure.git \
  --branch=main \
  --path=clusters/staging \
  --private-key-file=$HOME/.ssh/flux_deploy_key
```

Flux will:

- install controllers into the `flux-system` namespace
- commit `gotk-components.yaml` into the repository
- start reconciling from the specified path and branch

---

# What Bootstrap Creates

After bootstrap the repository will contain:

```
clusters/prod/flux-system/
├── gotk-components.yaml     ← all Flux controller manifests (CRDs + controllers)
├── gotk-sync.yaml           ← GitRepository (prod branch) + root Kustomization
└── kustomization.yaml       ← ties the above two files together
```

These manifests describe how Flux connects the cluster to Git. They are committed once and
reused on every future cluster rebuild — Flux does not need to be re-bootstrapped, just
re-applied with the SSH key.

---

# Saving the Deploy Key to Vault

> **Do this immediately after the first bootstrap.** This is the step that makes all future
> cluster rebuilds fully automated.

The SSH deploy key (`~/.ssh/flux_deploy_key`) is the credential Flux uses to pull from the
GitHub repository. On a fresh cluster, this key must be placed into the `flux-system` Secret
before Flux can sync. The `install-platform.yml` playbook handles this automatically — but
it reads the key from Ansible Vault.

## Step 1 — Extract the key material

```bash
# Private key (already on the RPi from when you generated it)
cat ~/.ssh/flux_deploy_key

# known_hosts entry for GitHub (use the official GitHub fingerprint)
ssh-keyscan github.com 2>/dev/null | grep ed25519
```

## Step 2 — Add to Ansible Vault

```bash
ansible-vault edit ansible/vars/vault.yml
```

Add the following entries (in addition to the existing `cloudflare_api_token`):

```yaml
flux_github_ssh_private_key: |
  -----BEGIN OPENSSH PRIVATE KEY-----
  <paste the full contents of ~/.ssh/flux_deploy_key here>
  -----END OPENSSH PRIVATE KEY-----

flux_github_known_hosts: "github.com ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C5okci41bzVz6S0k"
```

> **The private key must preserve its exact indentation.** The `|` block scalar in YAML
> means every line of the key is indented by two spaces. Ansible Vault encrypts this at rest.

## Step 3 — Verify

```bash
# Confirm vault decrypts and contains the key
ansible-vault view ansible/vars/vault.yml | grep flux_github_ssh_private_key
```

Once saved, `install-platform.yml` can rebuild the entire platform on any future cluster from a
single command — with no manual key handling required.

---

# Installing on a Rebuilt Cluster (Ansible)

This is the **standard procedure for all cluster rebuilds**. It assumes:

- k3s has been reinstalled via `install-cluster.yml`
- The Flux bootstrap manifests are committed in the repo (`clusters/prod/flux-system/`)
- The Flux SSH deploy key is stored in Ansible Vault

## Ansible Vault Setup (one-time per RPi)

The playbook reads secrets from `ansible/vars/vault.yml`, an Ansible Vault encrypted file.
The vault password lives only on the RPi and is never committed.

**Create the vault password file:**

```bash
# On the Raspberry Pi (10.0.10.10)
echo "your-chosen-vault-password" > ~/.vault_pass
chmod 600 ~/.vault_pass
```

**Create the encrypted vault file** (if it does not exist yet):

```bash
cd ~/homelab-infrastructure/ansible
ansible-vault create ansible/vars/vault.yml
```

Paste the following into the editor:

```yaml
cloudflare_api_token: "your-cloudflare-api-token-here"

flux_github_ssh_private_key: |
  -----BEGIN OPENSSH PRIVATE KEY-----
  <contents of ~/.ssh/flux_deploy_key>
  -----END OPENSSH PRIVATE KEY-----

flux_github_known_hosts: "github.com ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C5okci41bzVz6S0k"
```

Save and exit. The file is encrypted immediately. What gets committed to git looks like:

```
$ANSIBLE_VAULT;1.1;AES256
66386134653765363934346162623065613138646364646665...
```

**Edit the vault later** (e.g., to add secrets or rotate the Cloudflare token):

```bash
ansible-vault edit ansible/vars/vault.yml
```

## Run the Playbook

```bash
# From the Raspberry Pi, inside the ansible/ directory
cd ~/homelab-infrastructure/ansible

ansible-playbook -i inventory/homelab.yml \
  playbooks/lifecycle/install-platform.yml
```

> **Important:** Run from inside `ansible/`. Ansible loads `ansible.cfg` from the current
> working directory. Running from the repo root will fail to find the vault password file.

## What the Playbook Does

The playbook runs on the k3s control plane node (`tywin`) in five steps:

```mermaid
sequenceDiagram
    participant RPi as Raspberry Pi (ansible)
    participant CP as tywin (control plane)
    participant K8s as Kubernetes API
    participant Git as GitHub

    RPi->>CP: SSH connection
    CP->>K8s: Pre-flight: verify all nodes Ready

    Note over CP,K8s: Step 1 — Install flux2 CLI
    CP->>CP: curl fluxcd.io/install.sh (if not present)

    Note over CP,K8s: Step 2 — Apply Flux controllers
    RPi->>CP: Copy clusters/prod/flux-system/gotk-components.yaml
    CP->>K8s: kubectl apply gotk-components.yaml (CRDs + controllers)
    CP->>K8s: Wait for source/kustomize/helm/notification controllers Ready

    Note over CP,K8s: Step 3 — Create SSH secret
    CP->>K8s: Create flux-system namespace
    CP->>K8s: Create flux-system Secret from vault (SSH private key + known_hosts)

    Note over CP,K8s: Step 4 — Start GitOps sync
    RPi->>CP: Copy clusters/prod/flux-system/gotk-sync.yaml
    CP->>K8s: kubectl apply gotk-sync.yaml (GitRepository + Kustomization)
    K8s->>Git: source-controller pulls prod branch
    CP->>K8s: Wait for GitRepository Ready

    Note over CP,K8s: Step 5 — Wait for platform convergence
    K8s->>K8s: Flux reconciles platform-networking (MetalLB + Traefik)
    K8s->>K8s: Flux reconciles platform-security (cert-manager + ClusterIssuer)
    K8s->>K8s: Flux reconciles platform-storage (NFS provisioner)
    CP->>RPi: Print flux get kustomizations + helmreleases
```

The playbook explicitly waits for `platform-networking`, `platform-security`, and
`platform-storage` to reach `Ready` before declaring success. The full platform — MetalLB,
Traefik, cert-manager, wildcard certificate — is operational by the time the playbook exits.

## Expected Output

When complete, `flux get kustomizations` should show:

```
NAME                     REVISION             READY   MESSAGE
flux-system              prod@sha1:xxxxxxxx   True    Applied revision: prod@sha1:xxxxxxxx
platform-namespaces      prod@sha1:xxxxxxxx   True    Applied revision: ...
platform-networking      prod@sha1:xxxxxxxx   True    Applied revision: ...
platform-security        prod@sha1:xxxxxxxx   True    Applied revision: ...
platform-storage         prod@sha1:xxxxxxxx   True    Applied revision: ...
platform-upgrade         prod@sha1:xxxxxxxx   True    Applied revision: ...
platform-observability   prod@sha1:xxxxxxxx   True    Applied revision: ...
apps                     prod@sha1:xxxxxxxx   True    Applied revision: ...
```

And `flux get helmreleases -A`:

```
NAMESPACE       NAME        REVISION   READY   MESSAGE
metallb-system  metallb     0.14.9     True    Helm install succeeded
ingress         traefik     28.3.0     True    Helm upgrade succeeded
cert-manager    cert-manager v1.14.4   True    Helm install succeeded
```

---

# Flux Reconciliation Model

Flux continuously compares Git state with cluster state.

```
Git repository
      │
      ▼
Flux controllers
      │
      ▼
Cluster manifests
```

If drift occurs Flux corrects it automatically.

Example:

```
kubectl delete deployment grafana
```

Within minutes Flux restores the deployment because it still exists in Git.

---

# Verifying Flux Installation

Check the Flux namespace.

```
kubectl get pods -n flux-system
```

Expected:

```
source-controller
kustomize-controller
helm-controller
notification-controller
```

Check Flux health:

```
flux get all
```

All resources should report **Ready**.

---

# Operational Model After Flux

Once Flux is installed the operational model changes.

Instead of:

```
kubectl apply
```

engineers work through Git.

Example workflow:

```
1. edit manifest
2. commit change
3. push to Git
4. Flux reconciles cluster
```

This approach provides:

• version history
• safe rollbacks
• peer review via pull requests
• deterministic deployments

---

# Failure and Recovery

GitOps makes cluster recovery significantly easier.

If a cluster must be rebuilt, the full recovery sequence is:

```bash
# Step 1 — Reinstall k3s
ansible-playbook -i inventory/homelab.yml \
  playbooks/lifecycle/install-cluster.yml

# Step 2 — Bootstrap Flux and wait for platform convergence
cd ~/homelab-infrastructure/ansible
ansible-playbook -i inventory/homelab.yml \
  playbooks/lifecycle/install-platform.yml
```

That is the complete platform rebuild. Two commands. No manual `kubectl apply`, no `helm install`,
no manually recreating secrets. Everything is either in Git or in Ansible Vault.

Flux automatically reconstructs the full platform from Git:
- MetalLB → Traefik → cert-manager (in dependency order)
- All kustomizations and HelmReleases
- The wildcard TLS certificate (re-issued by cert-manager from Let's Encrypt)

Application data (PVC contents) is restored separately via Velero — see [Guide 08](./08-Cluster-Backups.md).

This is one of the most powerful advantages of GitOps: **the cluster is entirely disposable
and recoverable from a single vault + git repository.**

---

# Exit Criteria

Flux is correctly installed when:

✓ flux-system namespace exists
✓ Flux controllers are running
✓ repository successfully reconciles

Run:

```
flux get kustomizations
```

Status should be **Ready**.

---

# Next Guide

➡ **[05 — Cluster Identity & Scheduling](./05-Cluster-Identity-Scheduling.md)**

The next phase defines how workloads are distributed across nodes.
Cluster identity determines where infrastructure services, storage,
and applications are allowed to run.

---

## Navigation

| | Guide |
|---|---|
| ← Previous | [03 — Networking Platform](./03-Networking-Platform.md) |
| Current | **04 — GitOps Control Plane (FluxCD)** |
| → Next | [05 — Cluster Identity & Scheduling](./05-Cluster-Identity-Scheduling.md) |
