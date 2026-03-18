
# 10 — Platform Operations & Lifecycle Management
## Running the Platform Day‑to‑Day

**Author:** Kagiso Tjeane
**Difficulty:** ⭐⭐⭐⭐⭐⭐⭐⭐☆☆ (8/10)
**Guide:** 10 of 13

> Building a Kubernetes platform is only half the work.
> Operating it reliably over time is where real platform engineering begins.
>
> This chapter documents day‑to‑day operational lifecycle management:
>
> - cluster upgrades
> - node maintenance
> - platform component upgrades
> - incident response
> - routine operational checks

This guide aligns with the **Ansible playbooks present in the repository**, ensuring that routine operations remain repeatable and automated.

---

# The Platform Lifecycle

Once the platform is live, it enters a continuous operational cycle.

```mermaid
graph LR
    Deploy["Deploy<br/>Flux reconcile"] --> Observe["Observe<br/>Grafana + Alerts"]
    Observe --> Maintain["Maintain<br/>Ansible playbooks"]
    Maintain --> Upgrade["Upgrade<br/>HelmRelease bump + k3s Plans"]
    Upgrade --> Deploy
```

The goal is to keep the cluster:

- stable
- secure
- up to date
- fully observable

---

# Operational Responsibilities

| Layer | Responsibility | Primary Tool |
|-------|---------------|--------------|
| Infrastructure | node reboots, OS patching | Ansible |
| Kubernetes | k3s version upgrades | Ansible + system-upgrade-controller |
| Platform services | Traefik, cert-manager, monitoring upgrades | Flux (HelmRelease version bump) |
| Applications | deployment and scaling | Flux (Git commit) |
| Backups | daily etcd snapshots, Velero schedules | cron + Velero |
| Secrets | key rotation, re-encryption | SOPS + age |

---

# Routine Operational Checks

Run these checks periodically (recommend: daily, via Grafana or cron).

```bash
# Cluster node health
kubectl get nodes

# Non-running pods across all namespaces
kubectl get pods -A | grep -Ev 'Running|Completed'

# Flux reconciliation status
flux get kustomizations
flux get helmreleases -A

# Recent cluster events (last 30)
kubectl get events -A --sort-by='.lastTimestamp' | tail -30

# Backup health
ls -lht /mnt/backups/etcd/ | head -5
velero backup get | head -10
```

All of these checks are visible in Grafana when the monitoring stack is healthy.

---

# Node Maintenance with Ansible

The repository contains Ansible playbooks for all node operations.

```
ansible/playbooks/maintenance/
├── reboot-nodes.yml
└── upgrade-nodes.yml
```

Always run maintenance playbooks from the automation host with the kubeconfig present.

---

# Rebooting Nodes Safely

**Never reboot a node without draining it first.** Draining ensures running pods migrate before the node goes offline.

The reboot playbook handles the full sequence:

```bash
ansible-playbook ansible/playbooks/maintenance/reboot-nodes.yml
```

What the playbook does:

```
1. cordon node          (prevents new pod scheduling)
2. drain workloads      (evicts running pods gracefully)
3. reboot node
4. wait for node Ready  (polls until kubelet re-registers)
5. uncordon node        (returns node to scheduling pool)
```

To reboot a single node:

```bash
ansible-playbook ansible/playbooks/maintenance/reboot-nodes.yml --limit jaime
```

Verify after:

```bash
kubectl get nodes
```

---

# OS Package Upgrades

OS packages must be kept current for security. Run:

```bash
ansible-playbook ansible/playbooks/maintenance/upgrade-nodes.yml
```

Always upgrade **one node at a time** in this cluster. This prevents all workers from being unavailable simultaneously.

For worker nodes this is low-risk. The control-plane node (`tywin`) requires more care — ensure all workers are healthy before upgrading it.

---

# Upgrading k3s

k3s upgrades require care. With an embedded etcd datastore, the control-plane node is the most critical.

## Recommended Approach: System Upgrade Controller

The preferred method is the **k3s System Upgrade Controller**, which performs rolling upgrades via a Kubernetes `Plan` resource. This is deployed through Flux under `platform/upgrade/`.

```mermaid
graph TD
    Snap["1. Take etcd snapshot<br/>k3s-snapshot.sh"] --> Plan["2. Update Plan version in Git<br/>platform/upgrade/plan-server.yaml"]
    Plan --> CP["3. Controller upgrades tywin<br/>control-plane first"]
    CP --> W1["4. Controller upgrades jaime"]
    W1 --> W2["5. Controller upgrades tyrion"]
    W2 --> Verify["6. kubectl get nodes<br/>Verify all Ready"]
```

Trigger an upgrade by updating the k3s version in the `Plan` resource:

```yaml
# platform/upgrade/plan.yaml
spec:
  channel: https://update.k3s.io/v1-release/channels/stable
```

Or pin to a specific version:

```yaml
spec:
  version: v1.31.4+k3s1
```

Commit the change. Flux reconciles it. The controller upgrades control-plane first, then workers sequentially.

## Manual Upgrade (if system-upgrade-controller is unavailable)

```bash
# Step 1 — upgrade control-plane
ansible-playbook ansible/playbooks/lifecycle/install-cluster.yml --limit tywin

# Step 2 — verify control-plane is healthy
kubectl get nodes
kubectl get pods -A | grep -v Running | grep -v Completed

# Step 3 — upgrade workers one at a time
ansible-playbook ansible/playbooks/lifecycle/install-cluster.yml --limit jaime
kubectl wait --for=condition=Ready node/jaime --timeout=120s

ansible-playbook ansible/playbooks/lifecycle/install-cluster.yml --limit tyrion
kubectl wait --for=condition=Ready node/tyrion --timeout=120s
```

**Always take an etcd snapshot before any k3s upgrade:**

```bash
/usr/local/bin/k3s-snapshot.sh
```

---

# Upgrading Platform Components via GitOps

All platform components managed by Flux (Traefik, cert-manager, Prometheus, Loki, Velero) are upgraded by changing their chart version in Git.

Example: upgrading Traefik from `27.0.2` to `28.0.0`:

```yaml
# platform/upgrade/traefik/helmrelease.yaml
spec:
  chart:
    spec:
      chart: traefik
      version: "28.0.0"   # changed from 27.0.2
```

```bash
git add -p
git commit -m "chore: upgrade Traefik to 28.0.0"
git push
```

Flux reconciles the upgrade. Monitor progress:

```bash
flux get helmreleases -A --watch
```

Rollback if needed:

```bash
git revert HEAD
git push
```

---

# Scaling the Cluster

To add a worker node:

```
1. Provision new machine with Ubuntu Server
2. Update inventory/homelab.yml to add the new node
3. Run node preparation playbooks:
   ansible-playbook ansible/playbooks/security/disable-swap.yml --limit new-node
   ansible-playbook ansible/playbooks/security/firewall.yml --limit new-node
   ansible-playbook ansible/playbooks/security/ssh-hardening.yml --limit new-node
   ansible-playbook ansible/playbooks/security/time-sync.yml --limit new-node
   ansible-playbook ansible/playbooks/security/fail2ban.yml --limit new-node
4. Join the node:
   ansible-playbook ansible/playbooks/lifecycle/install-cluster.yml --limit new-node
5. Verify:
   kubectl get nodes
```

The scheduler automatically begins placing workloads on the new node.

---

# Incident Response — Structured Triage

When something breaks, structured triage finds the root cause faster than guessing.

## Step 1 — Establish cluster health baseline (30 seconds)

```bash
kubectl get nodes
kubectl get pods -A | grep -Ev 'Running|Completed'
flux get kustomizations
```

Interpretation:

- Node shows `NotReady` → check kubelet on the node: `ssh kagiso@<node-ip>` then `journalctl -u k3s -f`
- Flux reports `False` reconciliation → check the commit history and Flux logs
- Pods in `CrashLoopBackOff` → proceed to Step 3

## Step 2 — Scope the impact

```bash
kubectl get events -A --sort-by='.lastTimestamp' | tail -30
```

Events are often the fastest path to root cause. Look for `Failed`, `OOMKilled`, `BackOff`, or `Unhealthy` reasons.

## Step 3 — Inspect affected workloads

```bash
# Scheduling failures, OOMKilled, image pull errors
kubectl describe pod <pod-name> -n <namespace>

# Logs from the current container instance
kubectl logs <pod-name> -n <namespace>

# Logs from the previous (crashed) container instance
kubectl logs <pod-name> -n <namespace> --previous
```

## Step 4 — Check infrastructure components

```bash
kubectl get pods -n flux-system          # GitOps controllers
kubectl get pods -n ingress              # Traefik
kubectl get pods -n monitoring           # Prometheus / Grafana / Loki
kubectl get pods -n cert-manager         # Certificate controller
kubectl get pods -n metallb-system       # Load balancer
kubectl get pods -n velero               # Backup controller
```

If the monitoring stack is healthy, **Grafana dashboards are your first stop** — the alert that fired points directly at the affected component.

## Step 5 — Check Flux reconciliation errors

```bash
flux get all -A
flux logs --follow --level=error
```

---

# Common Operational Incidents

> Runbooks at `docs/operations/runbooks/` are living documents — use the first-check
> commands below until they are written. See
> [Guide 07 — Monitoring](./07-Monitoring-Observability.md#13-alert-response-runbooks)
> for additional inline guidance per alert type.

| Incident | First Check |
|----------|-------------|
| Pod in CrashLoopBackOff | `kubectl logs -n <ns> <pod> --previous` |
| Node shows NotReady | `kubectl describe node <node>` + `journalctl -u k3s` on the node |
| Certificate expired / pending | `kubectl describe certificate -n ingress` + `kubectl get challenges -A` |
| Disk pressure on node | `df -h` on the node + `kubectl get pvc -A` |
| High memory / CPU | Grafana Node Exporter dashboard — identify the process |
| Backup too old | `ls -lht /mnt/backups/etcd/ \| head -5` |
| Flux reconciliation failing | `flux logs --level=error` — check SOPS key and Git repo state |

---

# Disaster Recovery Workflow

If the cluster must be rebuilt entirely, follow this sequence.

## Prerequisites — verify before starting

| Item | Location | How to verify |
|------|----------|---------------|
| Ansible Vault password | `~/.vault_pass` on RPi | `ansible-vault view ansible/vars/vault.yml` |
| Flux SSH deploy key | in `ansible/vars/vault.yml` | `ansible-vault view ansible/vars/vault.yml \| grep flux_github_ssh_private_key` |
| Cloudflare API token | in `ansible/vars/vault.yml` | `ansible-vault view ansible/vars/vault.yml \| grep cloudflare` |
| etcd snapshot | TrueNAS NFS at `/mnt/tera/k3s-backups/` | `ls -lht /mnt/backups/etcd/` |
| age key (SOPS) | `~/age.key` on RPi | `ls -la ~/age.key` |

If the Flux SSH key is missing from vault, see [Guide 04 — Saving the Deploy Key to Vault](./04-Flux-GitOps.md#saving-the-deploy-key-to-vault).

## Rebuild Steps

```
1. Reinstall OS on affected nodes (if hardware failure)
2. Run Ansible security + preparation playbooks
3. Run Ansible install-cluster.yml   → fresh k3s cluster
4. Restore etcd from snapshot (only if control-plane data must be recovered)
5. Run Ansible install-platform.yml  → bootstraps Flux from vault + Git
6. Flux reconciles all platform services from Git automatically
7. Velero restores PVC data (application state)
8. Verify all services
```

## Commands

```bash
# On the Raspberry Pi (10.0.10.10), from ~/homelab-infrastructure/ansible

# Step 3 — reinstall k3s
ansible-playbook -i inventory/homelab.yml \
  playbooks/lifecycle/install-cluster.yml

# Step 5 — bootstrap Flux (reads SSH key from vault, applies gotk manifests, waits for Ready)
ansible-playbook -i inventory/homelab.yml \
  playbooks/lifecycle/install-platform.yml

# Step 7 — restore application data
velero restore create --from-backup <latest-backup-name>

# Step 8 — verify
flux get kustomizations
flux get helmreleases -A
kubectl get pods -A | grep -Ev 'Running|Completed'
```

> **No manual `flux bootstrap` or `helm install` commands are needed.** The deploy key is in
> vault, the platform manifests are in Git, and `install-platform.yml` wires them together.

Target: full platform operational **within 90–120 minutes** of starting the rebuild.

---

# Operational Checklist (Weekly)

```
□ kubectl get nodes — all Ready
□ kubectl get pods -A — no unexpected non-Running pods
□ flux get kustomizations — all Ready
□ flux get helmreleases -A — all Ready
□ ls /mnt/backups/etcd/ — snapshots present within last 24h
□ velero backup get — last backup Completed
□ Grafana — no active alerts
□ Grafana — node disk usage < 70%
□ Grafana — certificate expiry > 30 days for all certs
```

---

# Exit Criteria

Platform operations are considered stable when:

✓ maintenance playbooks run successfully without manual intervention
✓ k3s version upgrades complete via system-upgrade-controller
✓ platform component upgrades occur through GitOps HelmRelease bumps
✓ incident response triage produces root cause within 10 minutes
✓ monitoring confirms system health continuously

---

# Next Guide

➡ **[11 — Secrets Management (SOPS + age)](./11-Secrets-Management.md)**

The next guide covers how secrets are encrypted, stored in Git, and decrypted by Flux at reconciliation time.

---

## Navigation

| | Guide |
|---|---|
| ← Previous | [09 — Applications via GitOps](./09-Applications-GitOps.md) |
| Current | **10 — Platform Operations & Lifecycle Management** |
| → Next | [11 — Secrets Management](./11-Secrets-Management.md) |
