
# Alert Runbook — NodeNotReady

**Alert:** `KubeNodeNotReady`
**Threshold:** Node in NotReady state for > 5 minutes
**Severity:** Critical
**First response time:** 10 minutes

---

## What This Alert Means

A cluster node has lost contact with the Kubernetes control-plane, or the kubelet has reported that the node is not healthy. Pods on the node may be evicted and rescheduled on other nodes (after the `pod-eviction-timeout`, default 5 minutes).

---

## Step 1 — Assess the situation

```bash
kubectl get nodes
kubectl describe node <node-name>
```

Look at `Conditions` — what is the reason for `NotReady`?

| Condition | Meaning |
|-----------|---------|
| `KubeletNotReady` | kubelet cannot communicate with control-plane |
| `NetworkPluginNotReady` | CNI (flannel) is not functioning |
| `MemoryPressure` | node is out of memory |
| `DiskPressure` | node disk is full |
| `PIDPressure` | process table is exhausted |

---

## Step 2 — Attempt to reach the node

```bash
ping <node-ip>
ssh <user>@<node-ip>
```

**If the node is reachable via SSH:**

```bash
# Check kubelet status
systemctl status k3s-agent     # (on workers)
systemctl status k3s           # (on control-plane)

# Check kubelet logs
journalctl -u k3s-agent -n 50 --no-pager   # (workers)
journalctl -u k3s -n 50 --no-pager          # (control-plane)
```

**If the node is not reachable via SSH:**

The node may be powered off, crashed, or has a network failure. Check physical hardware or hypervisor console.

---

## Step 3 — Common fixes for reachable nodes

**kubelet stopped:**

```bash
# On the affected node:
sudo systemctl restart k3s-agent    # workers
sudo systemctl restart k3s          # control-plane
```

**Disk pressure causing NotReady:**
See [DiskPressure runbook](./DiskPressure.md).

**Memory pressure / OOM:**

```bash
# Check dmesg for OOM events
dmesg | grep -i "oom\|killed" | tail -20
```

If the node was OOMed, restart it cleanly:

```bash
sudo reboot
```

Then monitor it after it reconnects:

```bash
kubectl get nodes --watch
```

**Network plugin (flannel) not ready:**

```bash
kubectl get pods -n kube-system | grep flannel
kubectl logs -n kube-system <flannel-pod-name>
```

Restart the flannel pod:

```bash
kubectl delete pod -n kube-system <flannel-pod-name>
```

---

## Step 4 — If the node does not recover within 15 minutes

If the node remains NotReady after troubleshooting, treat it as a hardware failure and proceed to the [node-replacement runbook](../node-replacement.md).

While deciding, check the impact:

```bash
# Are critical workloads running on this node?
kubectl get pods -A -o wide | grep <node-name>

# Are they scheduled on other nodes?
kubectl get pods -A | grep -Ev 'Running|Completed'
```

---

## Step 5 — Verify recovery

```bash
kubectl get nodes
```

All nodes should show `Ready`.

```bash
kubectl get pods -A | grep -Ev 'Running|Completed'
```

Any pods that were on the failed node should have rescheduled and be running.

---

## Control-Plane Node Special Considerations

If `tywin` (the control-plane) goes NotReady:

- Worker nodes will continue running their existing pods.
- New pod scheduling is blocked until the control-plane recovers.
- `kubectl` commands will fail.
- Flux reconciliation will pause.

Recovering the control-plane is highest priority. If recovery fails, initiate the [cluster-rebuild runbook](../cluster-rebuild.md).
