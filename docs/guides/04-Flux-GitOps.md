
# 04 — GitOps Control Plane (FluxCD)
## Turning Git Into the Cluster API

**Author:** Kagiso Tjeane
**Difficulty:** ⭐⭐⭐⭐⭐⭐⭐⭐☆☆ (8/10)
**Guide:** 04 of 13

> Up to this point the cluster has been built using traditional infrastructure automation.
> Nodes were prepared with Ansible, Kubernetes was installed, and secrets encryption
> has been configured with SOPS + age.
>
> The next step is a major architectural shift:
>
> **Git becomes the control plane for the platform.**
>
> Once Flux is bootstrapped, it deploys the entire platform stack automatically:
> networking, security, storage, observability, backups, and upgrades — all from Git.

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

This repository uses a two-environment GitOps model:

- **Staging** (`clusters/staging/`) — a single-node k3s VM on Proxmox. Watches the `main` branch. Every commit to `main` lands here first.
- **Production** (`clusters/prod/`) — the three-node ThinkCentre cluster (tywin, jaime, tyrion). Watches the `prod` branch. Changes reach here only after staging validation.

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
    └── prod/                ← production Kustomize overlay
```

| Directory | Purpose |
|----------|---------|
`clusters/prod/flux-system` | Prod Flux sync — watches the `prod` branch |
`clusters/staging/flux-system` | Staging Flux sync — watches the `main` branch |
`platform/` | Shared platform services — same manifests for both environments |
`apps/base/` | Shared application manifests |
`apps/prod/` | Production Kustomize overlay |

## Promotion Model

Every change starts in `main` and is validated on staging before reaching production.

```mermaid
graph LR
    Dev["git push → main"] --> Staging["Staging cluster<br/>reconciles immediately"]
    Staging -->|"staging healthy"| Promote["git push origin main:prod"]
    Promote --> Prod["Prod cluster<br/>reconciles prod branch"]
    style Staging fill:#276749,color:#fff
    style Prod fill:#2b6cb0,color:#fff
```

**Promotion is a single git command:**

```bash
# After verifying staging is healthy:
git push origin main:prod
```

This fast-forwards the `prod` branch to the current `main` HEAD. The prod cluster's
source-controller detects the new commit on `prod` within one minute and begins reconciliation.

Staging is never bypassed. Unintentional configuration drift between environments is
prevented — both clusters pull from the same `platform/` and `apps/` paths; only the
branch differs. Intentional differences (e.g. production-specific resource limits) are
expressed through the `apps/prod/` Kustomize overlay.

> **Note:** Once the automated pipeline is active, do not run this command manually.
> It bypasses all staging health gates. The pipeline performs the same push as part of
> Stage 3, gated behind the full staging validation.

## Automated Gated Pipeline

Promotion is handled automatically by GitHub Actions (`.github/workflows/promote-to-prod.yml`).
Pushing to `main` triggers a fully gated 4-stage pipeline — **production is never touched unless
staging passes all health checks.**

```mermaid
flowchart TD
    Push["git push → main"] --> S1

    subgraph S1["Stage 1 — Validate"]
        V1["kubeconform schema validation"]
        V2["kustomize build apps/prod"]
        V3["kustomize build apps/staging"]
        V1 --> V2 --> V3
    end

    S1 -->|pass| S2

    subgraph S2["Stage 2 — Staging Health Check"]
        H1["Connect runner to homelab via Tailscale"]
        H2["Wait for staging GitRepository to sync this commit"]
        H3["kubectl wait kustomizations Ready"]
        H4["Check: no unhealthy pods"]
        H5["Smoke test: Traefik responds"]
        H1 --> H2 --> H3 --> H4 --> H5
    end

    S2 -->|"staging healthy"| S3

    subgraph S3["Stage 3 — Promote"]
        P1["git merge main → prod branch"]
        P2["git push origin prod"]
        P1 --> P2
    end

    S3 --> S4

    subgraph S4["Stage 4 — Production Health Check"]
        PH1["Connect runner to homelab via Tailscale"]
        PH2["Wait for prod GitRepository to sync promoted commit"]
        PH3["kubectl wait kustomizations Ready"]
        PH4["Check: no unhealthy pods"]
        PH5["Smoke test: Traefik at 10.0.10.110 responds"]
        PH1 --> PH2 --> PH3 --> PH4 --> PH5
    end

    S4 -->|pass| Done["Production reconciled ✓"]
    S1 -->|fail| Abort1["Pipeline blocked — no staging touch"]
    S2 -->|fail| Abort2["Pipeline blocked — no prod promotion"]
    S4 -->|fail| Alert["Run marked failed — investigate prod"]

    style S1 fill:#2d3748,color:#fff,stroke:#4a5568
    style S2 fill:#276749,color:#fff,stroke:#2f855a
    style S3 fill:#2b4c7e,color:#fff,stroke:#2c5282
    style S4 fill:#2b6cb0,color:#fff,stroke:#2c5282
    style Done fill:#276749,color:#fff
    style Abort1 fill:#742a2a,color:#fff
    style Abort2 fill:#742a2a,color:#fff
    style Alert fill:#744210,color:#fff
```

Health check jobs run on a **self-hosted runner installed on `bran` (10.0.10.10)**, which has
direct LAN access to both cluster API servers. No VPN or third-party tunnelling is required.
See [ADR-007](../adr/ADR-007-self-hosted-runners.md) for the full rationale and runner setup instructions.

The pipeline requires two GitHub repository secrets. Add these under
**Settings → Secrets and variables → Actions** in the GitHub repository.

| Secret | How to get it |
|--------|--------------|
| `STAGING_KUBECONFIG` | Contents of `/etc/rancher/k3s/k3s.yaml` on the staging VM (server = `10.0.10.31:6443`) |
| `PROD_KUBECONFIG` | Contents of `/etc/rancher/k3s/k3s.yaml` on `tywin` (server = `10.0.10.11:6443`) |

The `127.0.0.1` address in each kubeconfig must be replaced with the node's LAN IP so the
runner can reach it:

```bash
# On the staging VM:
sed 's/127.0.0.1/10.0.10.31/' /etc/rancher/k3s/k3s.yaml

# On tywin:
sed 's/127.0.0.1/10.0.10.11/' /etc/rancher/k3s/k3s.yaml
```

Paste the full output as the secret value.

---

# Pre-Bootstrap Checklist

**Do not bootstrap Flux until all of the following are true.** Flux reconciles the entire
platform stack immediately on first sync — if any prerequisite is missing, the corresponding
kustomization will fail and may require manual recovery.

| Prerequisite | When | How to verify |
|---|---|---|
| TrueNAS `core/k8s-volumes` NFS share exists and is exported | Before bootstrap | `showmount -e 10.0.10.80` — must list `/mnt/core/k8s-volumes` |
| `nfs-common` installed on all k3s nodes | Before bootstrap | `ansible k3s_controller,k3s_workers -m shell -a "dpkg -l nfs-common" --become` |
| `sops-age` secret created in `flux-system` namespace (Guide 03) | Before bootstrap | `kubectl get secret sops-age -n flux-system` |
| Cloudflare API token secret created in `cert-manager` namespace | Immediately after bootstrap, before watching convergence | `kubectl get secret cloudflare-api-token -n cert-manager` |

If `nfs-common` is missing, run `install-cluster.yml` again — it now installs it as the first
step. Or install it directly:

```bash
ansible k3s_controller,k3s_workers -i inventory/homelab.yml \
  -m apt -a "name=nfs-common state=present" --become
```

---

# Bootstrapping Flux

Flux is installed by **bootstrapping** the cluster to a Git repository.

This operation performs three actions:

1. installs Flux controllers in the cluster
2. commits Flux manifests into Git
3. connects the cluster to the repository

Once complete the cluster continuously monitors Git for changes.

> **This is a one-time operation per repository.** After the first bootstrap, the
> `gotk-sync.yaml` manifest (which tells Flux where to pull from and what path to reconcile)
> lives in `clusters/prod/flux-system/` and is committed to Git. On every subsequent cluster
> rebuild, the `install-platform.yml` Ansible playbook re-installs the Flux controllers via
> `flux install` and recreates the SSH secret from vault — no manual `flux bootstrap` call needed.

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

# Secrets Prerequisite

Flux decrypts SOPS-encrypted secrets using an age private key stored in the cluster.
This key **must exist before bootstrap** — if Flux reconciles an encrypted secret without
it, reconciliation fails immediately.

> **Complete [Guide 03 — Secrets Management](./03-Secrets-Management.md) before proceeding.**
> That guide covers age key generation, `.sops.yaml` configuration, and storing the
> `sops-age` Secret in the cluster. All of those steps must be done before Flux bootstrap.

Verify:

```bash
kubectl get secret sops-age -n flux-system
```

If this returns `NotFound`, go back to Guide 03 and complete the setup.

---

# First-Time Bootstrap (One-Time Per Repository)

> **This section is mandatory the first time this repository is used with a new cluster.**
> Once complete, all future cluster rebuilds use the
> **[Ansible playbook method](#installing-on-a-rebuilt-cluster-ansible)** instead — no manual
> `flux bootstrap` call is needed again.

## Step 1 — Bootstrap Both Clusters

With the secret in place, bootstrap each cluster. Both clusters use the same repository
and deploy key; only the branch and path differ.

**Bootstrap staging** (single-node VM at 10.0.10.31). First set up the kubeconfig on bran:

```bash
# Copy kubeconfig from staging VM and patch the address
scp kagiso@10.0.10.31:/etc/rancher/k3s/k3s.yaml ~/.kube/staging-config
sed -i 's/127.0.0.1/10.0.10.31/' ~/.kube/staging-config

# Activate for this session
export KUBECONFIG=~/.kube/staging-config

# Persist so future sessions don't need the export
echo 'export KUBECONFIG=~/.kube/staging-config' >> ~/.bashrc
```

Then bootstrap:

```bash
# SSH deploy key method (matches the automated rebuild playbook)
flux bootstrap git \
  --url=ssh://git@github.com/Kagiso-me/homelab-infrastructure.git \
  --branch=main \
  --path=clusters/staging \
  --private-key-file=$HOME/.ssh/flux_deploy_key

# Alternative: GitHub PAT method (simpler for first-time setup)
flux bootstrap github \
  --owner=Kagiso-me \
  --repository=homelab-infrastructure \
  --branch=main \
  --path=clusters/staging \
  --personal
```

After bootstrap completes, Flux immediately begins reconciling. It needs two secrets to
progress past the initial kustomizations. The first (`sops-age`) was created in Guide 03.
The second (Cloudflare API token) must be created now.

**Verify `sops-age` is present** (created in Guide 03 — should already exist):

```bash
kubectl get secret sops-age -n flux-system
```

If this returns `NotFound`, go back to [Guide 03 — Step 5](./03-Secrets-Management.md) and create it before continuing.

**Create the Cloudflare API token secret** (required for cert-manager DNS-01 wildcard cert):

```bash
# Get the token from vault
ansible-vault view ~/homelab-infrastructure/ansible/vars/vault.yml | grep cloudflare_api_token

kubectl create namespace cert-manager --dry-run=client -o yaml | kubectl apply -f -

kubectl create secret generic cloudflare-api-token \
  --namespace cert-manager \
  --from-literal=api-token=<token from vault output above>
```

Verify both secrets exist:

```bash
kubectl get secret sops-age -n flux-system
kubectl get secret cloudflare-api-token -n cert-manager
```

Once both are present, Flux will resolve `platform-networking` and the full dependency
chain will converge automatically. Watch progress with:

```bash
watch flux get kustomizations
```

**Bootstrap prod** (ThinkCentre cluster — tywin, jaime, tyrion). First set up the kubeconfig on bran:

```bash
# Copy kubeconfig from tywin (prod control plane) and patch the address
scp kagiso@10.0.10.11:/etc/rancher/k3s/k3s.yaml ~/.kube/prod-config
sed -i 's/127.0.0.1/10.0.10.11/' ~/.kube/prod-config

# Activate for this session
export KUBECONFIG=~/.kube/prod-config
```

> **Why the sed?** k3s writes `127.0.0.1:6443` into the kubeconfig — correct on `tywin`
> itself, but unreachable from `bran`. Replacing it with `tywin`'s LAN IP lets `flux` and
> `kubectl` reach the prod API server over the LAN.
>
> **Why set KUBECONFIG explicitly?** `flux bootstrap` targets whichever cluster the active
> kubeconfig points to. If your shell still has `KUBECONFIG=~/.kube/staging-config` from
> the staging step above, the prod bootstrap will silently install into staging again.
> Always confirm the active context before running bootstrap:
> ```bash
> kubectl config current-context
> ```

Then bootstrap:

```bash
# On the Raspberry Pi (10.0.10.10), with KUBECONFIG pointing at prod
flux bootstrap git \
  --url=ssh://git@github.com/Kagiso-me/homelab-infrastructure.git \
  --branch=prod \
  --path=clusters/prod \
  --private-key-file=$HOME/.ssh/flux_deploy_key
```

> **Note:** The `prod` branch must exist before bootstrapping prod. Create it if it
> doesn't exist yet: `git push origin main:prod`

**After prod bootstrap, create the Cloudflare API token secret on prod** — same as staging:

```bash
# With KUBECONFIG pointing at prod
kubectl create secret generic cloudflare-api-token \
  --namespace cert-manager \
  --from-literal=api-token=$(ansible-vault view ~/homelab-infrastructure/ansible/vars/vault.yml | grep cloudflare_api_token | awk '{print $2}' | tr -d '"')

kubectl get secret cloudflare-api-token -n cert-manager
```

Without this secret, cert-manager cannot complete the DNS-01 challenge and the wildcard TLS certificate will never become `Ready`.

Flux will for each cluster:

- install controllers into the `flux-system` namespace
- commit/update `gotk-sync.yaml` and `kustomization.yaml` into the repository
- start reconciling from the specified path and branch

---

# What Bootstrap Creates

After bootstrapping both clusters, the repository will contain:

```
clusters/
├── prod/flux-system/
│   ├── gotk-sync.yaml       ← GitRepository (prod branch) + root Kustomization
│   └── kustomization.yaml   ← ties gotk-sync.yaml into the Kustomize build
└── staging/flux-system/
    ├── gotk-sync.yaml       ← GitRepository (main branch) + root Kustomization
    └── kustomization.yaml
```

`gotk-sync.yaml` for each cluster defines which branch and path Flux reconciles. These files
are committed once and reused on every future cluster rebuild.

On rebuilds, `install-platform.yml` uses `flux install` to reinstall the controllers from
scratch, then applies the committed `gotk-sync.yaml` to reconnect Flux to the repo — no
re-bootstrap required.

---

# Saving the Deploy Key to Vault

> **Do this immediately after the first bootstrap.** This is the step that makes all future
> cluster rebuilds fully automated.

The SSH deploy key (`~/.ssh/flux_deploy_key`) is the credential Flux uses to pull from the
GitHub repository. On a fresh cluster, this key must be placed into the `flux-system` Secret
before Flux can sync. The `install-platform.yml` playbook handles this automatically — but
it reads the key from Ansible Vault.

> **First time? You need to create the vault file before you can add anything to it.**
> If `ansible/vars/vault.yml` does not exist yet, run these steps first:
>
> ```bash
> # 1. Create the vault password file (once per RPi — skip if it already exists)
> echo "your-chosen-vault-password" > ~/.vault_pass
> chmod 600 ~/.vault_pass
>
> # 2. Create the encrypted vault file
> cd ~/homelab-infrastructure/ansible
> ansible-vault create vars/vault.yml
> ```
>
> Paste this as the initial content (you will fill in the Flux key in Step 2 below).
> Replace the placeholder with the **real token from your password manager** — you stored it
> there in [Guide 00.5 — Step 6](./00.5-Infrastructure-Prerequisites.md):
>
> ```yaml
> cloudflare_api_token: "your-cloudflare-api-token-here"
> ```
>
> Save and exit. Then continue with Step 1.

## Step 1 — Extract the key material

```bash
# Private key (already on the RPi from when you generated it)
cat ~/.ssh/flux_deploy_key

# known_hosts entry for GitHub (use the official GitHub fingerprint)
ssh-keyscan github.com 2>/dev/null | grep ed25519
```

## Step 2 — Add to Ansible Vault

```bash
# If the vault file already exists:
ansible-vault edit ansible/vars/vault.yml
# If you just created it in the prerequisite step above, it is already open — just add the entries below.
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
- `clusters/prod/flux-system/gotk-sync.yaml` is committed in the repo (created during first-time bootstrap)
- The Flux SSH deploy key is stored in Ansible Vault

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

    Note over CP,K8s: Step 2 — Install Flux controllers
    CP->>CP: flux install --export (generates CRD + controller manifests)
    CP->>K8s: kubectl apply (CRDs + controllers)
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

On the **prod cluster** (after promoting to the `prod` branch):

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

On the **staging cluster** (after a `git push` to `main`):

```
NAME                        REVISION             READY   MESSAGE
flux-system                 main@sha1:xxxxxxxx   True    Applied revision: main@sha1:xxxxxxxx
platform-namespaces         main@sha1:xxxxxxxx   True    Applied revision: ...
platform-networking         main@sha1:xxxxxxxx   True    Applied revision: ...
platform-networking-config  main@sha1:xxxxxxxx   True    Applied revision: ...
platform-security           main@sha1:xxxxxxxx   True    Applied revision: ...
platform-observability      main@sha1:xxxxxxxx   True    Applied revision: ...
platform-storage            main@sha1:xxxxxxxx   True    Applied revision: ...
apps                        main@sha1:xxxxxxxx   True    Applied revision: ...
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

> **Production cluster** pulls from the `prod` branch. Ensure the `prod` branch is up to
> date before running `install-platform.yml` — if it was destroyed with the cluster, push
> the current `main`: `git push origin main:prod`

Application data (PVC contents) is restored separately via Velero — see [Guide 10](./10-Backups-Disaster-Recovery.md).

This is one of the most powerful advantages of GitOps: **the cluster is entirely disposable
and recoverable from a single vault + git repository.**

---

# Troubleshooting

## `platform-networking` stuck: "no matches for kind IPAddressPool"

**Symptom:** `flux get kustomizations` shows:

```
platform-networking   False   IPAddressPool/metallb-system/homelab-pool dry-run failed:
                              no matches for kind "IPAddressPool" in version "metallb.io/v1beta1"
```

And every other kustomization shows `dependency '…/platform-networking' is not ready`.

**Cause:** This is a Flux CRD bootstrapping problem. Flux dry-runs all resources in a
Kustomization before applying any of them. `IPAddressPool` is a MetalLB custom resource type —
the CRD only exists after MetalLB installs. If the MetalLB HelmRelease and the `IPAddressPool`
resource are in the same Kustomization, the dry-run fails on a fresh cluster because the CRD
hasn't been created yet.

**Resolution:** The fix is already applied in this repository. `metallb-config` (IPAddressPool +
L2Advertisement) lives in a separate `platform-networking-config` Kustomization that
`dependsOn: platform-networking`. This ensures MetalLB's HelmRelease installs first (creating
the CRDs), then the config is applied.

If you see this error after a fresh bootstrap, it usually means you are on an older version of
the repo that predates this fix. Pull the latest `main` and force a reconciliation:

```bash
flux reconcile kustomization flux-system --with-source
```

## `platform-security` stuck: "no matches for kind ServiceMonitor"

**Symptom:** `flux get kustomizations` shows:

```
platform-security   Unknown   Reconciliation in progress
```

And `kubectl get helmrelease -n cert-manager` shows:

```
cert-manager   False   Helm install failed: unable to build kubernetes objects from release manifest:
                       resource mapping not found for name: "cert-manager" namespace: "cert-manager"
                       from "": no matches for kind "ServiceMonitor" in version "monitoring.coreos.com/v1"
```

Every downstream kustomization (`platform-security-issuers`, `platform-observability`, `apps`) is blocked waiting on `platform-security`.

**Cause:** Another CRD bootstrapping chicken-and-egg. cert-manager's HelmRelease has
`prometheus.servicemonitor.enabled: true`, which tells Helm to create a `ServiceMonitor`
resource. `ServiceMonitor` is a kube-prometheus-stack CRD — it only exists after
`platform-observability` installs. But `platform-observability` depends on `platform-security`
(cert-manager). They block each other indefinitely.

**Resolution:** The fix is already applied in this repository. `platform/security/cert-manager/helmrelease.yaml`
sets `prometheus.servicemonitor.enabled: false` on bootstrap. Once `platform-observability`
is healthy and kube-prometheus-stack CRDs exist, you can re-enable it:

```yaml
# platform/security/cert-manager/helmrelease.yaml
values:
  prometheus:
    enabled: true
    servicemonitor:
      enabled: true   # safe to enable after platform-observability is Ready
```

Commit and push — Flux will upgrade the HelmRelease and create the ServiceMonitor against
the now-existing CRDs.

If you see this on a fresh bootstrap after the fix is already committed, Flux may have
exhausted its install retries (configured as 3) before the fix landed. In that case, Flux
will not retry automatically — the HelmRelease stays in a failed state indefinitely.

**Force a retry:**

```bash
flux reconcile helmrelease cert-manager -n cert-manager
```

If that does not trigger a new install attempt (the HelmRelease is already marked failed),
reset it by suspending and resuming:

```bash
flux suspend helmrelease cert-manager -n cert-manager
flux resume helmrelease cert-manager -n cert-manager
```

Then watch it converge:

```bash
flux get helmrelease cert-manager -n cert-manager --watch
```

Once cert-manager goes `READY: True`, the downstream chain (`platform-security-issuers` →
`platform-observability` → `apps`) unblocks automatically.

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

➡ **[05 — Networking: MetalLB & Traefik](./05-Networking-MetalLB-Traefik.md)**

The next guide introduces the networking layer that exposes services
from the cluster to the local network.

---

## Navigation

| | Guide |
|---|---|
| ← Previous | [03 — Secrets Management](./03-Secrets-Management.md) |
| Current | **04 — Flux GitOps Bootstrap** |
| → Next | [05 — Networking: MetalLB & Traefik](./05-Networking-MetalLB-Traefik.md) |
