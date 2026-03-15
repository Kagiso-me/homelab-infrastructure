
# Alert Runbook — NodeMemoryHigh

**Alert:** `NodeMemoryUtilizationHigh`
**Threshold:** > 85% memory used on any node for > 10 minutes
**Severity:** Warning at 85%, Critical at 95%
**First response time:** 30 minutes (Warning), 5 minutes (Critical)

---

## What This Alert Means

A cluster node is under memory pressure. At high utilization, the Linux kernel's OOM killer may begin terminating processes, which in a Kubernetes context means pods being killed with exit code 137.

---

## Step 1 — Identify which node

```bash
kubectl get nodes -o wide
kubectl top nodes
```

Identify the node with high memory usage.

---

## Step 2 — Identify top memory consumers on the node

```bash
kubectl top pods -A --sort-by=memory | head -20
```

Or filter to pods on the specific node:

```bash
kubectl get pods -A -o wide | grep <node-name>
```

Then check their memory usage:

```bash
kubectl top pods -n <namespace>
```

---

## Step 3 — Check for recent memory growth

Open Grafana → **Kubernetes / Compute Resources / Node** dashboard.

Look at the memory usage graph for the affected node. Is it:

- **Gradually increasing?** — likely a memory leak in one of the running applications
- **Sudden spike?** — likely a new deployment or increased load
- **Sustained high?** — the workload has grown beyond node capacity

---

## Step 4 — Identify the largest consumers

```bash
# On the node itself (SSH):
free -h
ps aux --sort=-%mem | head -20
```

---

## Step 5 — Remediation options

**Option A — Pod has a memory leak (gradual increase)**

Restart the affected pod:

```bash
kubectl rollout restart deployment/<deployment-name> -n <namespace>
```

Monitor whether memory drops after restart. If this is a recurring pattern, investigate the application or increase memory limits and open an issue.

**Option B — Workload has grown legitimately (sustained high)**

If the node genuinely needs more memory for its current workload:

1. Add a worker node (see [node-replacement.md](../node-replacement.md) for the procedure, which also covers adding nodes).
2. Move some workloads to the other worker by adjusting pod affinity/anti-affinity rules.
3. Reduce replica count if over-provisioned.

**Option C — Prometheus TSDB consuming too much memory**

Prometheus is the most common memory consumer. Check its settings:

```bash
kubectl get helmrelease kube-prometheus-stack -n monitoring -o yaml | grep -A5 retention
```

Reduce retention period if storage is being traded for memory:
```yaml
prometheus:
  prometheusSpec:
    retention: 7d          # reduce from 15d
    retentionSize: "10GB"  # add size cap
```

**Option D — Critical: node approaching OOM (> 95%)**

Immediately reduce load on the node:

```bash
# Cordon the node to stop new scheduling
kubectl cordon <node-name>

# Identify and gracefully delete the largest non-critical pods
kubectl delete pod <pod-name> -n <namespace>
```

This allows the OOM killer to not fire, giving time to diagnose. After the immediate pressure is relieved, investigate and resolve the root cause before uncordoning.

---

## Step 6 — Verify recovery

```bash
kubectl top nodes
```

Memory usage should be below 85%. Unordon the node if it was cordoned:

```bash
kubectl uncordon <node-name>
```

---

## Long-term Actions

- Set memory `requests` and `limits` on all deployments. Requests allow the scheduler to avoid overcommitting. Limits prevent a single pod from consuming all node memory.
- Review Grafana → **Kubernetes / Compute Resources / Cluster** for memory request vs actual usage ratio per namespace.
- If nodes are consistently above 70% memory usage, plan capacity expansion.
