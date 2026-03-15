
# Runbook — Upgrading k3s via system-upgrade-controller

**Scenario:** A new k3s release is available and the cluster must be upgraded. Upgrades are performed GitOps-style via system-upgrade-controller Plans managed by FluxCD.

**Severity:** Maintenance (planned)
**RTO Estimate:** ~15–25 minutes for a rolling upgrade across all three nodes
**Impact:** Each node is cordoned and drained in sequence during upgrade. Single-replica workloads will experience brief downtime (~2–3 minutes per node). Multi-replica workloads remain available.

> **Related runbooks:** [cluster-rebuild](./cluster-rebuild.md) | [alerts/NodeNotReady](./alerts/NodeNotReady.md)

---

## What This Alert Means

This is a planned maintenance runbook, not an alert response. Trigger it when:

- A new k3s patch or minor version is released
- A CVE fix is available in a newer k3s build
- Kubernetes version skew between nodes is detected

k3s releases: https://github.com/k3s-io/k3s/releases

system-upgrade-controller reads `Plan` CRDs from the cluster and applies the specified version to matching nodes using a drain-upgrade-uncordon sequence. The control-plane node (tywin) is upgraded first, then workers.

---

## Quick Reference

| Item | Value |
|------|-------|
| Current version check | `kubectl get nodes -o wide` |
| Plan manifest location | `clusters/homelab/platform/upgrade/plans/` |
| system-upgrade-controller namespace | `system-upgrade` |
| Upgrade order | tywin → jaime → tyrion |
| Expected per-node upgrade time | ~3–5 minutes |
| Rollback method | Re-pin previous version in Git; drain and reinstall k3s manually |

---

## Step 1 — Check current k3s versions

```bash
kubectl get nodes -o wide
```

Expected output (shows current version in `VERSION` column):

```
NAME     STATUS   ROLES                  VERSION
tywin    Ready    control-plane,master   v1.31.4+k3s1
jaime    Ready    <none>                 v1.31.4+k3s1
tyrion   Ready    <none>                 v1.31.4+k3s1
```

Also confirm system-upgrade-controller is running:

```bash
kubectl get pods -n system-upgrade
# Expected: system-upgrade-controller pod in Running state
```

---

## Step 2 — Identify the target version

Check the k3s release page or GitHub releases API:

```bash
curl -s https://api.github.com/repos/k3s-io/k3s/releases/latest \
  | grep '"tag_name"'
# Example output: "tag_name": "v1.31.5+k3s1"
```

Review the release notes for any breaking changes before proceeding.

---

## Step 3 — Update the Plan manifests in Git

The upgrade Plans live in the GitOps repository. Locate and edit them:

```bash
# On the automation host (or any machine with a git clone of the repo):
ls clusters/homelab/platform/upgrade/plans/
# Expected files: server-plan.yaml  agent-plan.yaml
```

Edit the server Plan (targets the control-plane):

```bash
# In clusters/homelab/platform/upgrade/plans/server-plan.yaml
# Update the version field:
```

```yaml
spec:
  version: v1.31.5+k3s1    # <-- change this line
```

Edit the agent Plan (targets worker nodes):

```yaml
spec:
  version: v1.31.5+k3s1    # <-- change this line to match
```

Commit and push the changes:

```bash
git add clusters/homelab/platform/upgrade/plans/
git commit -m "chore: upgrade k3s to v1.31.5+k3s1"
git push origin main
```

---

## Step 4 — Trigger Flux reconciliation

Flux polls every few minutes, but you can force an immediate apply:

```bash
flux reconcile kustomization platform-upgrade --with-source
```

Verify the Plan objects are updated in the cluster:

```bash
kubectl get plans -n system-upgrade
```

Expected output:

```
NAME          AGE   VERSION        LATEST
server-plan   5s    v1.31.5+k3s1   v1.31.5+k3s1
agent-plan    5s    v1.31.5+k3s1   v1.31.5+k3s1
```

---

## Step 5 — Monitor the upgrade

Watch the upgrade Jobs that system-upgrade-controller creates per node:

```bash
kubectl get jobs -n system-upgrade --watch
```

Watch upgrade pods as they run:

```bash
kubectl get pods -n system-upgrade --watch
```

Typical progression — the controller upgrades one node at a time:

```
apply-server-plan-on-tywin-...   0/1   Pending    → Running → Completed
apply-agent-plan-on-jaime-...    0/1   Pending    → Running → Completed
apply-agent-plan-on-tyrion-...   0/1   Pending    → Running → Completed
```

While a node is being upgraded, it will briefly show `SchedulingDisabled`:

```bash
kubectl get nodes --watch
```

Each node should return to `Ready` within 5 minutes of its upgrade Job completing.

---

## Step 6 — Verify the upgrade

```bash
kubectl get nodes -o wide
```

All three nodes should show the new version:

```
NAME     STATUS   ROLES                  VERSION
tywin    Ready    control-plane,master   v1.31.5+k3s1
jaime    Ready    <none>                 v1.31.5+k3s1
tyrion   Ready    <none>                 v1.31.5+k3s1
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

---

## Expected Timeline

| Phase | Duration |
|-------|----------|
| Git commit + push | 2 min |
| Flux reconcile to apply Plan update | 1–3 min |
| tywin (control-plane) upgrade | 4–6 min |
| jaime upgrade | 3–5 min |
| tyrion upgrade | 3–5 min |
| Verification | 2 min |
| **Total** | **~15–25 min** |

---

## Rollback Procedure

If a node fails to come back `Ready` after upgrade, or if application breakage is detected:

### Option A — Revert the Plan version in Git

```bash
# Revert server-plan.yaml and agent-plan.yaml to the previous version
git revert HEAD
git push origin main
flux reconcile kustomization platform-upgrade --with-source
```

system-upgrade-controller will detect the version downgrade and apply the old version to each node in sequence.

### Option B — Manual k3s reinstall on a specific node

If one node is stuck and cannot self-recover:

```bash
# SSH to the affected node (example: jaime):
ssh kagiso@10.0.10.12

# Stop k3s-agent
sudo systemctl stop k3s-agent

# Uninstall k3s
sudo /usr/local/bin/k3s-agent-uninstall.sh

# Exit and re-run the install playbook for just this node:
ansible-playbook playbooks/lifecycle/install-cluster.yml --limit jaime
```

After reinstall, the node will rejoin with the version specified by the install playbook. Update the playbook's k3s version pin to match the working cluster version.

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
# Plans show the reverted version
```

---

## Decision Table

| Symptom | Action |
|---------|--------|
| Plan objects not updating after git push | `flux reconcile kustomization platform-upgrade --with-source` |
| Upgrade Job stays Pending >5 min | Check controller logs: `kubectl logs -n system-upgrade deployment/system-upgrade-controller` |
| Node stuck SchedulingDisabled | Check Job pod logs: `kubectl logs -n system-upgrade <job-pod-name>` |
| Node NotReady after upgrade | See [NodeNotReady runbook](./alerts/NodeNotReady.md); consider rollback |
| Version skew between nodes | Run upgrade again; controller will catch missing nodes |
| control-plane upgrade fails | Immediately revert Plan version in Git; check API server: `journalctl -u k3s -n 50` on tywin |
