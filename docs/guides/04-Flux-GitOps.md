
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

---

# Generate a Deploy Key

Flux authenticates to Git using SSH.

Create a key:

```
ssh-keygen -t ed25519 -f ~/.ssh/flux_deploy_key -C "flux@cluster"
```

This produces:

```
~/.ssh/flux_deploy_key
~/.ssh/flux_deploy_key.pub
```

Add the public key to the Git repository as a **Deploy Key** with write access.

---

# Installing the Flux CLI

Install the CLI tool:

```
curl -s https://fluxcd.io/install.sh | sudo bash
```

Verify installation:

```
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

# Install SOPS
SOPS_VERSION=3.8.1
curl -LO https://github.com/getsops/sops/releases/download/v${SOPS_VERSION}/sops-v${SOPS_VERSION}.linux.amd64
chmod +x sops-v${SOPS_VERSION}.linux.amd64
sudo mv sops-v${SOPS_VERSION}.linux.amd64 /usr/local/bin/sops
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
  --from-file=age.agekey=~/age.key
```

Verify:

```bash
kubectl get secret sops-age -n flux-system
```

---

# Bootstrapping the Cluster

> **Both prod and staging clusters have already been bootstrapped.**
> These steps are preserved here for reference when re-bootstrapping after a cluster rebuild.

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
├── gotk-components.yaml     ← all Flux controller manifests
├── gotk-sync.yaml           ← GitRepository (prod branch) + Kustomization
└── kustomization.yaml
```

These manifests describe how Flux connects the cluster to Git.

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

If a cluster must be rebuilt:

```
reinstall Kubernetes
bootstrap Flux
```

Flux automatically reconstructs the platform from Git.

This is one of the most powerful advantages of GitOps.

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
