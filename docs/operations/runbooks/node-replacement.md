
# Runbook — Node Replacement

**Scenario:** A worker node has failed and must be replaced. The replacement is either the same machine (reimaged) or a new machine.

**Applies to:** Worker nodes (jaime, tyrion). For control-plane failure, use the [cluster-rebuild runbook](./cluster-rebuild.md).

**Impact:** Pods on the failed node will be rescheduled to the remaining healthy worker. If only one worker remains, all workloads run on a single node. Service availability is maintained for multi-replica workloads.

---

## Step 1 — Assess the Failure

Determine whether the node is truly dead or temporarily unavailable.

```bash
kubectl get nodes
```

A genuinely failed node shows `NotReady` for more than 5 minutes. Kubernetes moves pods off the node after `--pod-eviction-timeout` (default 5 minutes in k3s).

Check the node's condition:

```bash
kubectl describe node <node-name>
```

Look for `Conditions` showing `Ready: False` and the `Reason` field.

If the node is simply rebooting or temporarily unreachable, wait 5 minutes before proceeding. Many `NotReady` events resolve without intervention.

---

## Step 2 — Cordon and Drain the Failed Node

Even if the node is already dead, drain it to clear the Kubernetes records cleanly.

```bash
# Prevent new pods from scheduling on the node
kubectl cordon <node-name>

# Evict running pods (use --ignore-daemonsets for DaemonSet pods)
kubectl drain <node-name> \
  --ignore-daemonsets \
  --delete-emptydir-data \
  --timeout=120s
```

If the node is completely unreachable, `--force` may be required:

```bash
kubectl drain <node-name> \
  --ignore-daemonsets \
  --delete-emptydir-data \
  --force \
  --timeout=60s
```

---

## Step 3 — Delete the Node from the Cluster

```bash
kubectl delete node <node-name>
```

Verify:

```bash
kubectl get nodes
```

The failed node should no longer appear.

---

## Step 4 — Remove the k3s Agent from the Old Machine

If the node's machine is still accessible (e.g., soft failure, will be reimaged), purge k3s:

```bash
ansible-playbook playbooks/lifecycle/purge-k3s.yml --limit <node-name>
```

If the machine is completely unresponsive, skip this step and proceed to reimaging.

---

## Step 5 — Prepare the Replacement Node

Reimage or prepare the replacement machine. Ensure:

- Ubuntu Server installed
- SSH access from the automation host established
- Correct IP assigned (same IP as the failed node, or update the inventory)

If the IP changes, update `ansible/k3s/inventory/homelab.yml` before proceeding.

---

## Step 6 — Run Node Preparation Playbooks

```bash
cd kubernetes/ansible/k3s

ansible-playbook playbooks/maintenance/upgrade-nodes.yml --limit <node-name>
ansible-playbook playbooks/security/disable-swap.yml --limit <node-name>
ansible-playbook playbooks/security/time-sync.yml --limit <node-name>
ansible-playbook playbooks/security/firewall.yml --limit <node-name>
ansible-playbook playbooks/security/ssh-hardening.yml --limit <node-name>
ansible-playbook playbooks/security/fail2ban.yml --limit <node-name>
```

---

## Step 7 — Join the Node to the Cluster

```bash
ansible-playbook playbooks/lifecycle/install-cluster.yml --limit <node-name>
```

The playbook installs k3s agent and joins the node using the existing cluster token.

---

## Step 8 — Verify

```bash
# Node shows Ready
kubectl get nodes

# Pods rescheduled correctly
kubectl get pods -A -o wide | grep <node-name>
```

Wait for Kubernetes to schedule workloads onto the new node. This happens automatically within a few minutes.

---

## Step 9 — Check PVC Reattachment

If workloads that were on the failed node had PVCs, verify they successfully attached to the new node:

```bash
kubectl get pvc -A
```

All PVCs should show `Bound`. If any PVC shows `Lost`, the volume data may still be present on TrueNAS but the binding is broken. Investigate with:

```bash
kubectl describe pvc <pvc-name> -n <namespace>
```

For NFS-backed volumes, data is stored on TrueNAS and not tied to a specific node. PVCs should rebind cleanly.

---

## Verification Checklist

```
□ kubectl get nodes — all nodes Ready
□ kubectl get pods -A — all pods Running or Completed
□ kubectl get pvc -A — all PVCs Bound
□ Grafana shows metrics for the new node
□ Workloads distributed across all workers
```

---

## Expected Timeline

| Step | Duration |
|------|----------|
| Failure assessment | 5 min |
| Drain + delete | 2 min |
| Node preparation | 10 min |
| Cluster join | 3 min |
| Verification | 5 min |
| **Total** | **~25 min** |
