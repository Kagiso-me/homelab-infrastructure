# Runbook - Upgrading k3s via system-upgrade-controller

**Scenario:** A new k3s release is available and the cluster must be upgraded. Upgrades are performed GitOps-style via system-upgrade-controller Plans managed by FluxCD.

**Severity:** Maintenance (planned)
**RTO Estimate:** ~15-25 minutes for a rolling upgrade across all three HA server nodes
**Impact:** Each node is cordoned and drained in sequence during upgrade. Single-replica workloads will experience brief downtime (~2-3 minutes per node). Multi-replica workloads should remain available.

> **Related runbooks:** [cluster-rebuild](./cluster-rebuild.md) | [alerts/NodeNotReady](./alerts/NodeNotReady.md)

---

## What This Runbook Means

This is a planned maintenance runbook, not an alert response. Trigger it when:

- a new k3s patch or minor version is released
- a CVE fix is available in a newer k3s build
- Kubernetes version skew between nodes is detected

k3s releases: https://github.com/k3s-io/k3s/releases

system-upgrade-controller reads `Plan` CRDs from the cluster and applies the specified version to matching nodes using a drain-upgrade-uncordon sequence. In this cluster, a single Plan targets all three HA server nodes, and the controller upgrades them one at a time.

---

## Quick Reference

| Item | Value |
|------|-------|
| Current version check | `kubectl get nodes -o wide` |
| Plan manifest location | `platform/upgrade/upgrade-plans/plan-server.yaml` |
| system-upgrade-controller namespace | `system-upgrade` |
| Plan name | `k3s-server` |
| API endpoint during upgrade | `https://10.0.10.100:6443` |
| Expected per-node upgrade time | ~3-5 minutes |
| Rollback method | Re-pin previous version in Git; drain and reinstall k3s manually if required |

---

## Step 1 - Check current k3s versions

```bash
kubectl get nodes -o wide
```

Expected output (shows current version in `VERSION` column):

```text
NAME     STATUS   ROLES                  VERSION
tywin    Ready    control-plane,master   v1.31.4+k3s1
tyrion   Ready    control-plane,master   v1.31.4+k3s1
jaime    Ready    control-plane,master   v1.31.4+k3s1
```

Also confirm system-upgrade-controller is running:

```bash
kubectl get pods -n system-upgrade
# Expected: system-upgrade-controller pod in Running state
```

---

## Step 2 - Identify the target version

Check the k3s release page or GitHub releases API:

```bash
curl -s https://api.github.com/repos/k3s-io/k3s/releases/latest \
  | grep '"tag_name"'
# Example output: "tag_name": "v1.31.5+k3s1"
```

Review the release notes for any breaking changes before proceeding.

---

## Step 3 - Update the Plan manifest in Git

The upgrade Plan lives in the GitOps repository.

```bash
# On the automation host (or any machine with a git clone of the repo):
Get-Content platform/upgrade/upgrade-plans/plan-server.yaml
```

Update the version field:

```yaml
spec:
  version: v1.31.5+k3s1    # change this line
```

Commit and push the change:

```bash
git add platform/upgrade/upgrade-plans/plan-server.yaml
git commit -m "chore: upgrade k3s to v1.31.5+k3s1"
git push origin main
```

---

## Step 4 - Trigger Flux reconciliation

Flux polls every few minutes, but you can force an immediate apply:

```bash
flux reconcile kustomization platform-upgrade --with-source
```

Verify the Plan object is updated in the cluster:

```bash
kubectl get plans -n system-upgrade
```

Expected output:

```text
NAME         AGE   VERSION        LATEST
k3s-server   5s    v1.31.5+k3s1   v1.31.5+k3s1
```

---

## Step 5 - Monitor the upgrade

Watch the upgrade Jobs that system-upgrade-controller creates per node:

```bash
kubectl get jobs -n system-upgrade --watch
```

Watch upgrade pods as they run:

```bash
kubectl get pods -n system-upgrade --watch
```

Typical progression - the controller upgrades one node at a time:

```text
apply-k3s-server-on-tywin-...    0/1   Pending -> Running -> Completed
apply-k3s-server-on-tyrion-...   0/1   Pending -> Running -> Completed
apply-k3s-server-on-jaime-...    0/1   Pending -> Running -> Completed
```

While a node is being upgraded, it will briefly show `SchedulingDisabled`:

```bash
kubectl get nodes --watch
```

Each node should return to `Ready` within 5 minutes of its upgrade Job completing.

---

## Step 6 - Verify the upgrade

```bash
kubectl get nodes -o wide
```

All three nodes should show the new version:

```text
NAME     STATUS   ROLES                  VERSION
tywin    Ready    control-plane,master   v1.31.5+k3s1
tyrion   Ready    control-plane,master   v1.31.5+k3s1
jaime    Ready    control-plane,master   v1.31.5+k3s1
```

Check that no pods are stuck:

```bash
kubectl get pods -A | grep -Ev 'Running|Completed|Succeeded'
```

Verify Flux is still healthy:

```bash
flux get all -A | grep -v True
# Expected: no output (all objects reconciled)
```

Verify the API stayed reachable through the VIP:

```bash
kubectl cluster-info
# Server should still resolve via 10.0.10.100
```

---

## Expected Timeline

| Phase | Duration |
|-------|----------|
| Git commit + push | 2 min |
| Flux reconcile to apply Plan update | 1-3 min |
| First server upgrade | 4-6 min |
| Second server upgrade | 3-5 min |
| Third server upgrade | 3-5 min |
| Verification | 2 min |
| **Total** | **~15-25 min** |

---

## Rollback Procedure

If a node fails to come back `Ready` after upgrade, or if application breakage is detected:

### Option A - Revert the Plan version in Git

```bash
git revert HEAD
git push origin main
flux reconcile kustomization platform-upgrade --with-source
```

system-upgrade-controller will detect the version downgrade and apply the older version to each matching node in sequence.

### Option B - Manual k3s reinstall on a specific node

If one node is stuck and cannot self-recover:

```bash
# SSH to the affected node (example: jaime):
ssh kagiso@10.0.10.13

# Stop k3s
sudo systemctl stop k3s

# Uninstall k3s
sudo /usr/local/bin/k3s-uninstall.sh

# Exit and re-run the install playbook for just this node:
ansible-playbook -i ansible/inventory/homelab.yml ansible/playbooks/lifecycle/install-cluster.yml --limit jaime
```

After reinstall, the node will rejoin with the version specified by the install playbook. Keep the install version pin aligned with the cluster target version.

---

## Verify Recovery (after rollback)

```bash
kubectl get nodes -o wide
# All nodes show the rollback version

kubectl get pods -A | grep -Ev 'Running|Completed|Succeeded'
# No pods stuck

flux get kustomizations
# All kustomizations Ready

kubectl get plans -n system-upgrade
# Plan shows the reverted version
```

---

## Decision Table

| Symptom | Action |
|---------|--------|
| Plan object not updating after git push | `flux reconcile kustomization platform-upgrade --with-source` |
| Upgrade Job stays Pending >5 min | Check controller logs: `kubectl logs -n system-upgrade deployment/system-upgrade-controller` |
| Node stuck SchedulingDisabled | Check Job pod logs: `kubectl logs -n system-upgrade <job-pod-name>` |
| Node NotReady after upgrade | See [NodeNotReady runbook](./alerts/NodeNotReady.md); consider rollback |
| Version skew between nodes | Re-run the plan reconciliation; controller will catch missing nodes |
| Server upgrade fails | Immediately revert Plan version in Git; check API server: `journalctl -u k3s -n 50` on the affected node |
