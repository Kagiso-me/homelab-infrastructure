# Kubernetes Alert Runbooks

| Field | Value |
|-------|-------|
| File | kubernetes-runbooks.md |
| Covers | PodCrashLooping, PodCrashLoopingFrequent, PodNotReady, PodOOMKilled, DeploymentReplicasMismatch, PVCUsageHigh, PVCUsageCritical, PVCPending, CertificateExpiringSoon, CertificateExpiringCritical, CertificateNotReady, FluxReconciliationFailed, FluxReconciliationStalled, FluxSuspended, TraefikHighErrorRate, TraefikHighLatency |
| Last Updated | 2026-03-15 |

**Note:** All `kubectl` commands are run from the RPi control hub at `10.0.10.10`. SSH there first: `ssh kagiso@10.0.10.10`

---

## Table of Contents

1. [PodCrashLooping](#podcrashlooping)
2. [PodCrashLoopingFrequent](#podcrashloogingfrequent)
3. [PodNotReady](#podnotready)
4. [PodOOMKilled](#podoomkilled)
5. [DeploymentReplicasMismatch](#deploymentreplicasmismatch)
6. [PVCUsageHigh](#pvcusagehigh)
7. [PVCUsageCritical](#pvcusagecritical)
8. [PVCPending](#pvcpending)
9. [CertificateExpiringSoon](#certificateexpiringsoon)
10. [CertificateExpiringCritical](#certificateexpiringcritical)
11. [CertificateNotReady](#certificatenotready)
12. [FluxReconciliationFailed](#fluxreconciliationfailed)
13. [FluxReconciliationStalled](#fluxreconciliationstalled)
14. [FluxSuspended](#fluxsuspended)
15. [TraefikHighErrorRate](#traefikhigherrorrate)
16. [TraefikHighLatency](#traefikhighlatency)

---

## PodCrashLooping

| Field | Value |
|-------|-------|
| Severity | Warning |
| Threshold | Pod restart count > 3 in last 15 minutes |
| First Response | 30 minutes |

### What This Alert Means

A pod is repeatedly crashing and being restarted by Kubernetes. The container starts, fails (exits with non-zero code or segfaults), and k3s restarts it in an exponential backoff loop. Common causes: misconfiguration, missing secrets, dependency unavailable, or OOM.

### Diagnostic Steps

1. SSH to the RPi and identify the crashing pod:
   ```bash
   ssh kagiso@10.0.10.10
   kubectl get pods -A | grep -E "CrashLoopBackOff|Error|OOMKilled"
   ```

2. Get detailed pod events and status:
   ```bash
   kubectl describe pod <pod-name> -n <namespace>
   # Look for: Last State, Exit Code, Reason, Events section
   ```

3. Check current and previous container logs:
   ```bash
   kubectl logs <pod-name> -n <namespace> --tail=100
   kubectl logs <pod-name> -n <namespace> --previous --tail=100
   ```

4. Identify the exit code from describe output and cross-reference:

   | Exit Code | Meaning |
   |-----------|---------|
   | 1 | General application error |
   | 137 | OOM killed (SIGKILL) |
   | 139 | Segfault (SIGSEGV) |
   | 143 | Graceful termination (SIGTERM) |

5. Check if the pod can access its required secrets/configmaps:
   ```bash
   kubectl get secret -n <namespace> | grep <expected-secret>
   kubectl get configmap -n <namespace>
   ```

6. Check the node the pod is scheduled on for resource pressure:
   ```bash
   kubectl get pod <pod-name> -n <namespace> -o wide  # note the node
   kubectl describe node <node-name> | grep -A10 "Conditions:"
   ```

7. Check if there are SOPS-related errors (secrets not decrypted):
   ```bash
   kubectl get secret -n <namespace> -o yaml | grep -i "Error\|failed"
   flux logs --kind=Kustomization --all-namespaces | grep -i "decrypt\|sops" | tail -20
   ```

### Decision Table

| Condition | Action |
|-----------|--------|
| Exit code 137 | See [PodOOMKilled](#podoomkilled) |
| Missing secret | Check SOPS decryption; re-reconcile Flux |
| ConfigMap missing | Force Flux reconciliation: `flux reconcile kustomization <name>` |
| Application config error | Check app-specific configuration; redeploy |
| Dependency (DB, etc.) unavailable | Fix dependency first, then restart pod |

### Verify Recovery

```bash
ssh kagiso@10.0.10.10
kubectl get pod <pod-name> -n <namespace>
# Status should be: Running
kubectl get pod <pod-name> -n <namespace> -o jsonpath='{.status.containerStatuses[0].restartCount}'
# Restart count should stop incrementing
```

---

## PodCrashLoopingFrequent

| Field | Value |
|-------|-------|
| Severity | Critical |
| Threshold | Pod restart count > 10 in last 15 minutes |
| First Response | 10 minutes |

### What This Alert Means

A pod is crashing very rapidly — this is beyond a transient startup failure and indicates a persistent issue that is actively consuming cluster resources and may be affecting other workloads through resource contention.

### Diagnostic Steps

Follow all steps in [PodCrashLooping](#podcrashlooping), then additionally:

1. Check how many restarts have occurred:
   ```bash
   ssh kagiso@10.0.10.10
   kubectl get pod <pod-name> -n <namespace> -o jsonpath='{.status.containerStatuses[0].restartCount}'
   ```

2. Check cluster-wide resource pressure caused by rapid restarts:
   ```bash
   kubectl top nodes
   kubectl top pods -A --sort-by=cpu | head -20
   ```

3. Consider temporarily stopping the crash loop to protect the cluster:
   ```bash
   # Scale down the deployment:
   kubectl scale deployment <name> -n <namespace> --replicas=0
   # Or suspend the Flux HelmRelease:
   flux suspend helmrelease <name> -n <namespace>
   ```

4. Examine if a recent GitOps change triggered this:
   ```bash
   flux get kustomizations -A
   git -C ~/homelab-infrastructure log --oneline -10
   ```

5. If caused by a bad deployment, roll back:
   ```bash
   kubectl rollout undo deployment/<name> -n <namespace>
   kubectl rollout status deployment/<name> -n <namespace>
   ```

### Verify Recovery

```bash
ssh kagiso@10.0.10.10
kubectl get pods -A | grep -E "CrashLoopBackOff|Error"
# No pods should appear in crash loop state
```

---

## PodNotReady

| Field | Value |
|-------|-------|
| Severity | Warning |
| Threshold | Pod not in Ready state for > 5 minutes |
| First Response | 30 minutes |

### What This Alert Means

A pod is running but its readiness probe is failing, or the pod is stuck in `Pending`, `Init`, or `Terminating` state. Traffic is not being routed to this pod. May indicate a misconfigured health check, resource unavailability, or stuck termination.

### Diagnostic Steps

1. Identify the not-ready pod:
   ```bash
   ssh kagiso@10.0.10.10
   kubectl get pods -A | grep -v "Running\|Completed" | grep -v "NAME"
   ```

2. Describe the pod to see conditions and events:
   ```bash
   kubectl describe pod <pod-name> -n <namespace>
   # Check: Conditions section for "Ready: False"
   # Check: Events for scheduling failures, image pull errors, etc.
   ```

3. For `Pending` pods, check scheduling issues:
   ```bash
   kubectl get events -n <namespace> --sort-by='.lastTimestamp' | tail -20
   kubectl describe pod <pod-name> -n <namespace> | grep -A5 "Events:"
   ```

4. For init container issues:
   ```bash
   kubectl logs <pod-name> -n <namespace> -c <init-container-name>
   kubectl get pod <pod-name> -n <namespace> -o jsonpath='{.spec.initContainers[*].name}'
   ```

5. For `Terminating` pods stuck (finalizer issue):
   ```bash
   kubectl get pod <pod-name> -n <namespace> -o yaml | grep -A5 "finalizers:"
   # If stuck and no finalizer should apply:
   kubectl patch pod <pod-name> -n <namespace> -p '{"metadata":{"finalizers":[]}}' --type=merge
   ```

6. Check if the node has the required labels/taints for scheduling:
   ```bash
   kubectl get nodes --show-labels
   kubectl describe pod <pod-name> -n <namespace> | grep -A5 "Node-Selectors:\|Tolerations:"
   ```

### Decision Table

| Condition | Action |
|-----------|--------|
| Image pull error | Check image name/tag; verify registry access from cluster |
| Insufficient resources | See [DeploymentReplicasMismatch](#deploymentreplicasmismatch); check node capacity |
| PVC not bound | See [PVCPending](#pvcpending) |
| Readiness probe failing | Check probe endpoint; review app health logs |
| Stuck Terminating | Remove finalizers (carefully); force delete as last resort |

### Verify Recovery

```bash
ssh kagiso@10.0.10.10
kubectl get pod <pod-name> -n <namespace>
# Status: Running, READY column should show e.g. 1/1
```

---

## PodOOMKilled

| Field | Value |
|-------|-------|
| Severity | Warning |
| Threshold | Pod container OOMKilled (exit code 137) at least once |
| First Response | 30 minutes |

### What This Alert Means

A container was killed by the Linux OOM killer because it exceeded its memory limit. If limits are set too low, this will keep recurring. If no limit is set, the container consumed all available node memory.

### Diagnostic Steps

1. Confirm OOM kill and check which container:
   ```bash
   ssh kagiso@10.0.10.10
   kubectl get pods -A -o wide | grep -v "Running\|Completed"
   kubectl describe pod <pod-name> -n <namespace> | grep -B2 -A5 "OOMKilled\|137"
   ```

2. Check the current memory limit and actual usage:
   ```bash
   kubectl get pod <pod-name> -n <namespace> -o jsonpath='{.spec.containers[0].resources}' | python3 -m json.tool
   kubectl top pod <pod-name> -n <namespace> --containers
   ```

3. Check node memory at the time of the kill:
   ```bash
   kubectl describe node <node-name> | grep -A10 "Allocated resources:"
   kubectl top node <node-name>
   ```

4. Review what the container was doing when it OOMed (last logs before kill):
   ```bash
   kubectl logs <pod-name> -n <namespace> --previous --tail=50
   ```

5. Find the Helm values or Kustomize patch that sets the memory limit in the GitOps repo:
   ```bash
   # On RPi:
   grep -r "memory" ~/homelab-infrastructure/kubernetes/ | grep -i "<app-name>"
   ```

6. Increase the memory limit in the GitOps repo and commit:
   ```bash
   # Edit the relevant HelmRelease values or kustomization patch
   # Then let Flux reconcile, or force it:
   flux reconcile kustomization <name> -n <namespace>
   ```

### Decision Table

| Condition | Action |
|-----------|--------|
| Limit set too low | Increase memory limit in HelmRelease/Kustomization values |
| No limit set | Add `resources.limits.memory` to pod spec |
| App has genuine memory leak | Investigate app metrics; consider scheduled restart |
| Node running out of memory | See node memory alert runbook; check other pods |

### Verify Recovery

```bash
ssh kagiso@10.0.10.10
kubectl get pod <pod-name> -n <namespace>
# Confirm Running with 0 recent restarts
kubectl top pod <pod-name> -n <namespace> --containers
# Confirm memory usage is well under the new limit
```

---

## DeploymentReplicasMismatch

| Field | Value |
|-------|-------|
| Severity | Warning |
| Threshold | `desired replicas != ready replicas` for > 15 minutes |
| First Response | 30 minutes |

### What This Alert Means

A Deployment (or StatefulSet) has fewer ready pods than the desired replica count. This means the application is degraded — some traffic may be unserved or the workload is running with reduced capacity.

### Diagnostic Steps

1. Find the mismatched deployment:
   ```bash
   ssh kagiso@10.0.10.10
   kubectl get deployments -A | awk '{if ($3 != $4) print}'
   kubectl get statefulsets -A | awk '{if ($2 != $3) print}'
   ```

2. Check why the replica isn't coming up:
   ```bash
   kubectl get pods -n <namespace> -l app=<label>
   kubectl describe pod <failing-pod> -n <namespace>
   ```

3. Check if the node it was scheduled on is available:
   ```bash
   kubectl get nodes
   # If a node is NotReady:
   ssh kagiso@10.0.10.1x  # connect to that node (11/12/13)
   sudo systemctl status k3s k3s-agent
   ```

4. Check if resource quotas are blocking scheduling:
   ```bash
   kubectl describe resourcequota -n <namespace>
   kubectl get limitrange -n <namespace>
   ```

5. Check if there's an active rollout:
   ```bash
   kubectl rollout status deployment/<name> -n <namespace>
   kubectl rollout history deployment/<name> -n <namespace>
   ```

6. Check cluster capacity across all three nodes:
   ```bash
   kubectl top nodes
   kubectl describe nodes | grep -A5 "Allocated resources"
   ```

### Decision Table

| Condition | Action |
|-----------|--------|
| Node NotReady (jaime/tyrion) | See [NodeNotReady.md](NodeNotReady.md) |
| Pod in CrashLoopBackOff | See [PodCrashLooping](#podcrashlooping) |
| Insufficient CPU/memory | Redistribute workloads or add resources |
| Image pull failure | Check image registry connectivity; verify image tag exists |
| Active rollout stuck | `kubectl rollout undo deployment/<name> -n <namespace>` |

### Verify Recovery

```bash
ssh kagiso@10.0.10.10
kubectl get deployment <name> -n <namespace>
# READY and UP-TO-DATE columns should match DESIRED
```

---

## PVCUsageHigh

| Field | Value |
|-------|-------|
| Severity | Warning |
| Threshold | PVC usage > 80% |
| First Response | 2 hours |

### What This Alert Means

A Persistent Volume Claim is more than 80% full. Left unaddressed, it will hit the critical threshold and potentially cause the application to fail when it cannot write to disk.

### Diagnostic Steps

1. Identify which PVC is filling up:
   ```bash
   ssh kagiso@10.0.10.10
   # Prometheus query (run via kubectl exec into prometheus pod):
   kubectl get pvc -A
   ```

2. Find which node the PVC is mounted on and check usage:
   ```bash
   kubectl get pvc <pvc-name> -n <namespace> -o wide
   # Note the volume name, then find the pod using it:
   kubectl get pods -n <namespace> -o wide | grep <pvc-pod>
   ```

3. SSH to the node and check actual disk usage:
   ```bash
   # If on jaime (10.0.10.12):
   ssh kagiso@10.0.10.12
   df -h /var/lib/rancher/k3s/storage/  # for local-path PVCs
   du -sh /var/lib/rancher/k3s/storage/pvc-*
   ```

4. Identify what's consuming space inside the pod:
   ```bash
   # Back on RPi:
   kubectl exec -it <pod-name> -n <namespace> -- df -h
   kubectl exec -it <pod-name> -n <namespace> -- du -sh /* 2>/dev/null | sort -rh | head -20
   ```

5. Check if the PVC is backed by NFS (TrueNAS) or local storage:
   ```bash
   kubectl get pvc <pvc-name> -n <namespace> -o yaml | grep storageClassName
   ```

### Decision Table

| Condition | Action |
|-----------|--------|
| Log files consuming space | Add log rotation or increase retention policy |
| Database growing | Archive old data or resize PVC |
| NFS-backed PVC | Check TrueNAS pool usage; see [TrueNASDiskFull](truenas-runbooks.md#zfspoolscrubberrors) |
| Can resize PVC | Patch PVC size (if StorageClass allows expansion) |

### Verify Recovery

```bash
ssh kagiso@10.0.10.10
kubectl exec -it <pod-name> -n <namespace> -- df -h /data
# Usage should be below 80%
```

---

## PVCUsageCritical

| Field | Value |
|-------|-------|
| Severity | Critical |
| Threshold | PVC usage > 95% |
| First Response | 15 minutes |

### What This Alert Means

A PVC is nearly full. The application will very likely fail to write data imminently (within minutes to hours), causing crashes, data corruption, or service outage.

### Diagnostic Steps

Follow all steps in [PVCUsageHigh](#pvcusagehigh), then act immediately:

1. Free space urgently — identify and delete the largest files:
   ```bash
   kubectl exec -it <pod-name> -n <namespace> -- bash
   find / -type f -size +100M 2>/dev/null | sort -k5 -rn
   # Delete log files, temp files, old data as appropriate
   ```

2. If the PVC can be expanded (check StorageClass `allowVolumeExpansion: true`):
   ```bash
   kubectl get storageclass
   # If expansion is allowed:
   kubectl patch pvc <pvc-name> -n <namespace> \
     -p '{"spec":{"resources":{"requests":{"storage":"<new-size>Gi"}}}}'
   ```

3. If space cannot be freed fast enough, scale down the affected deployment to prevent corruption:
   ```bash
   kubectl scale deployment <name> -n <namespace> --replicas=0
   ```

4. Offload data to TrueNAS if possible:
   ```bash
   kubectl exec -it <pod-name> -n <namespace> -- tar czf - /data | \
     ssh admin@10.0.10.80 "cat > /mnt/archive/emergency-backup/$(date +%Y%m%d).tar.gz"
   ```

### Verify Recovery

```bash
ssh kagiso@10.0.10.10
kubectl exec -it <pod-name> -n <namespace> -- df -h /data
# Usage must be below 90% before restarting any scaled-down deployments
```

---

## PVCPending

| Field | Value |
|-------|-------|
| Severity | Warning |
| Threshold | PVC in `Pending` state for > 5 minutes |
| First Response | 30 minutes |

### What This Alert Means

A PVC has been created but cannot be bound to a PersistentVolume. The pod using this PVC will remain in `Pending` state and not start. Common causes: no available storage, NFS provisioner down, or storage class misconfiguration.

### Diagnostic Steps

1. Find the pending PVC:
   ```bash
   ssh kagiso@10.0.10.10
   kubectl get pvc -A | grep Pending
   kubectl describe pvc <pvc-name> -n <namespace>
   # Look at Events section — usually explains why binding failed
   ```

2. Check if the storage provisioner is running:
   ```bash
   # For local-path-provisioner (default k3s):
   kubectl get pods -n kube-system | grep local-path
   kubectl logs -n kube-system -l app=local-path-provisioner --tail=30

   # For NFS provisioner:
   kubectl get pods -A | grep nfs
   ```

3. Check available PersistentVolumes:
   ```bash
   kubectl get pv
   kubectl get pv | grep Available
   ```

4. Check if the storage class exists and is correct:
   ```bash
   kubectl get storageclass
   kubectl describe storageclass <class-name>
   ```

5. If NFS-backed storage, verify NFS exports on TrueNAS:
   ```bash
   ssh admin@10.0.10.80 "showmount -e localhost"
   # From a k3s node:
   ssh kagiso@10.0.10.11 "showmount -e 10.0.10.80"
   ```

### Decision Table

| Condition | Action |
|-----------|--------|
| local-path-provisioner crashlooping | Restart: `kubectl rollout restart deployment/local-path-provisioner -n kube-system` |
| NFS provisioner down | Check NFS provisioner pod; verify TrueNAS NFS service |
| StorageClass not found | Fix PVC spec to use correct StorageClass name |
| Node has no space | Free disk on worker nodes; check [DiskPressure.md](DiskPressure.md) |

### Verify Recovery

```bash
ssh kagiso@10.0.10.10
kubectl get pvc <pvc-name> -n <namespace>
# Status should change from Pending to Bound
```

---

## CertificateExpiringSoon

| Field | Value |
|-------|-------|
| Severity | Warning |
| Threshold | TLS certificate expires in < 21 days |
| First Response | 4 hours |

### What This Alert Means

A cert-manager managed certificate will expire in under 21 days and has not yet been renewed. Cert-manager normally renews at 2/3 of certificate lifetime; failure to renew at this stage indicates a problem with the ACME challenge or cert-manager itself.

### Diagnostic Steps

1. List all certificates and their expiry:
   ```bash
   ssh kagiso@10.0.10.10
   kubectl get certificates -A
   kubectl get certificates -A -o custom-columns=\
   'NAME:.metadata.name,NAMESPACE:.metadata.namespace,READY:.status.conditions[0].status,EXPIRY:.status.notAfter'
   ```

2. Describe the expiring certificate:
   ```bash
   kubectl describe certificate <cert-name> -n <namespace>
   # Check: Status, Conditions, Events
   ```

3. Check the associated CertificateRequest and Order:
   ```bash
   kubectl get certificaterequest -n <namespace>
   kubectl describe certificaterequest <cr-name> -n <namespace>
   kubectl get order -n <namespace>
   kubectl describe order <order-name> -n <namespace>
   ```

4. Check cert-manager logs:
   ```bash
   kubectl logs -n cert-manager -l app=cert-manager --since=2h | grep -E "error|Error|certificate" | tail -30
   ```

5. Check if the ACME challenge is working (HTTP-01 or DNS-01):
   ```bash
   kubectl get challenge -n <namespace>
   kubectl describe challenge -n <namespace>
   ```

6. For HTTP-01 challenges, verify Traefik is routing the challenge path:
   ```bash
   curl -v http://<domain>/.well-known/acme-challenge/test
   ```

7. Force a manual certificate renewal:
   ```bash
   kubectl annotate certificate <cert-name> -n <namespace> \
     cert-manager.io/issuer-name- \
     cert-manager.io/issue-temporary-certificate-
   # Or delete the cert to force re-issue:
   kubectl delete certificaterequest -n <namespace> <cr-name>
   ```

### Decision Table

| Condition | Action |
|-----------|--------|
| HTTP-01 challenge failing | Check Traefik ingress; verify port 80 accessible externally |
| DNS-01 challenge failing | Check DNS provider credentials secret |
| cert-manager pod crashlooping | Restart cert-manager; check logs |
| Rate limited by Let's Encrypt | Wait or use staging; check for certificate duplicates |

### Verify Recovery

```bash
ssh kagiso@10.0.10.10
kubectl get certificate <cert-name> -n <namespace>
# READY should be True, and expiry date should be ~90 days out
```

---

## CertificateExpiringCritical

| Field | Value |
|-------|-------|
| Severity | Critical |
| Threshold | TLS certificate expires in < 7 days |
| First Response | 30 minutes |

### What This Alert Means

A certificate will expire in under 7 days. If not renewed, HTTPS services will show browser warnings or fail entirely. Immediate intervention required.

### Diagnostic Steps

Follow all steps from [CertificateExpiringSoon](#certificateexpiringsoon), then escalate:

1. Check if the cert has been trying to renew and failing:
   ```bash
   ssh kagiso@10.0.10.10
   kubectl describe certificate <cert-name> -n <namespace> | grep -A20 "Status:"
   ```

2. Check for ACME challenge errors specifically:
   ```bash
   kubectl get challenges -A
   kubectl describe challenge -A | grep -A10 "Reason:"
   ```

3. If automated renewal is completely stuck, consider manual intervention using certbot directly on Traefik node (10.0.10.110):
   ```bash
   ssh kagiso@10.0.10.110
   # If certbot is available:
   certbot renew --force-renewal --cert-name <domain>
   ```

4. As a stopgap, check if a valid certificate exists elsewhere (TrueNAS, Docker host) that can be temporarily used.

5. See full certificate failure runbook: [certificate-failure.md](../certificate-failure.md)

### Verify Recovery

```bash
ssh kagiso@10.0.10.10
kubectl get certificate <cert-name> -n <namespace> -o jsonpath='{.status.notAfter}'
# Should be ~90 days in the future
```

---

## CertificateNotReady

| Field | Value |
|-------|-------|
| Severity | Warning |
| Threshold | Certificate `Ready` condition is `False` for > 10 minutes |
| First Response | 30 minutes |

### What This Alert Means

A cert-manager Certificate resource exists but is not in a Ready state. This means TLS is not functioning for the associated ingress/service.

### Diagnostic Steps

1. Find not-ready certificates:
   ```bash
   ssh kagiso@10.0.10.10
   kubectl get certificates -A | grep -v "True"
   kubectl describe certificate <cert-name> -n <namespace>
   ```

2. Check the full chain: Certificate → CertificateRequest → Order → Challenge:
   ```bash
   kubectl get certificaterequest,order,challenge -n <namespace>
   ```

3. Check cert-manager controller logs:
   ```bash
   kubectl logs -n cert-manager deploy/cert-manager --since=1h | grep -i "error\|<cert-name>" | tail -40
   ```

4. Check the ClusterIssuer or Issuer is ready:
   ```bash
   kubectl get clusterissuer
   kubectl describe clusterissuer <issuer-name>
   ```

5. Verify the secret referenced by the Certificate exists:
   ```bash
   kubectl get secret -n <namespace> | grep <secret-name-from-cert-spec>
   ```

### Verify Recovery

```bash
ssh kagiso@10.0.10.10
kubectl get certificate -A
# All should show READY = True
```

---

## FluxReconciliationFailed

| Field | Value |
|-------|-------|
| Severity | Warning |
| Threshold | Flux Kustomization or HelmRelease reconciliation fails |
| First Response | 30 minutes |

### What This Alert Means

A FluxCD Kustomization or HelmRelease failed to reconcile. The desired state from the Git repository is not being applied to the cluster. The cluster may be drifting from the GitOps source of truth.

### Diagnostic Steps

1. Identify failed reconciliations:
   ```bash
   ssh kagiso@10.0.10.10
   flux get kustomizations -A | grep -v "True\|False.*False"
   flux get helmreleases -A | grep -v True
   ```

2. Get detailed status of the failing resource:
   ```bash
   flux get kustomization <name> -n <namespace>
   kubectl describe kustomization <name> -n <namespace>
   ```

3. Check Flux controller logs:
   ```bash
   # For Kustomization failures:
   kubectl logs -n flux-system deploy/kustomize-controller --since=1h | grep -i "error\|fail" | tail -30

   # For HelmRelease failures:
   kubectl logs -n flux-system deploy/helm-controller --since=1h | grep -i "error\|fail" | tail -30
   ```

4. Check if the GitRepository source is syncing:
   ```bash
   flux get sources git -A
   kubectl describe gitrepository -n flux-system
   ```

5. Check for SOPS decryption failures (common cause):
   ```bash
   kubectl logs -n flux-system deploy/kustomize-controller --since=1h | grep -i "decrypt\|sops\|age" | tail -20
   ```

6. Force a reconciliation attempt:
   ```bash
   flux reconcile kustomization <name> -n flux-system --with-source
   ```

7. Check if the age key secret exists in flux-system:
   ```bash
   kubectl get secret -n flux-system sops-age
   ```

### Decision Table

| Condition | Action |
|-----------|--------|
| SOPS decrypt error | Verify age key secret; re-apply from backup |
| Git source not syncing | Check GitHub/Gitea connectivity from cluster |
| Helm chart not found | Check chart repository URL and version |
| Invalid YAML in repo | Fix YAML in GitOps repo; Flux will auto-retry |
| Dependency not ready | Check which resource it depends on |

### Verify Recovery

```bash
ssh kagiso@10.0.10.10
flux get kustomizations -A
flux get helmreleases -A
# All should show READY=True, STATUS=Applied revision
```

---

## FluxReconciliationStalled

| Field | Value |
|-------|-------|
| Severity | Warning |
| Threshold | Flux resource in `Stalled` condition for > 15 minutes |
| First Response | 30 minutes |

### What This Alert Means

A Flux resource is in a `Stalled` state, meaning Flux has detected a situation where retrying will not help without human intervention. This is different from a transient failure.

### Diagnostic Steps

1. Find stalled resources:
   ```bash
   ssh kagiso@10.0.10.10
   flux get all -A | grep -i stalled
   kubectl get kustomizations,helmreleases -A -o wide | grep -i stalled
   ```

2. Get the stall reason:
   ```bash
   kubectl describe kustomization <name> -n <namespace> | grep -A10 "Stalled\|Message:"
   kubectl describe helmrelease <name> -n <namespace> | grep -A10 "Stalled\|Message:"
   ```

3. Common stall reasons:
   - Helm upgrade failed and rollback also failed
   - Resource validation failed (invalid CRD/schema)
   - Missing CRD that a HelmRelease depends on

4. For stuck HelmRelease (upgrade failed):
   ```bash
   # Check Helm release history:
   helm history <release-name> -n <namespace>

   # Force reset the HelmRelease state:
   flux suspend helmrelease <name> -n <namespace>
   helm uninstall <release-name> -n <namespace>
   flux resume helmrelease <name> -n <namespace>
   ```

5. Check if a CRD is missing:
   ```bash
   kubectl get crds | grep <expected-crd>
   ```

### Verify Recovery

```bash
ssh kagiso@10.0.10.10
flux get all -A | grep -v "True"
# No resources should show Stalled
```

---

## FluxSuspended

| Field | Value |
|-------|-------|
| Severity | Warning |
| Threshold | Any Flux resource suspended for > 2 hours unexpectedly |
| First Response | 1 hour |

### What This Alert Means

A Flux Kustomization or HelmRelease has been suspended, pausing GitOps reconciliation for that resource. This may be intentional (maintenance) or left suspended accidentally after troubleshooting.

### Diagnostic Steps

1. Check all suspended Flux resources:
   ```bash
   ssh kagiso@10.0.10.10
   flux get kustomizations -A | grep True  # suspended shows True in suspended column
   flux get helmreleases -A | grep True
   # Or:
   kubectl get kustomizations,helmreleases -A -o jsonpath='{range .items[?(@.spec.suspend==true)]}{.kind}/{.metadata.namespace}/{.metadata.name}{"\n"}{end}'
   ```

2. Determine if the suspension was intentional (check recent activity):
   ```bash
   kubectl describe kustomization <name> -n <namespace> | grep -E "Suspend|annotation|Last.*Handled"
   git -C ~/homelab-infrastructure log --oneline --since="3 hours ago"
   ```

3. If suspension is confirmed unintentional, resume:
   ```bash
   flux resume kustomization <name> -n flux-system
   flux resume helmrelease <name> -n <namespace>
   ```

4. If suspension was for maintenance that is now complete, resume and verify:
   ```bash
   flux resume kustomization --all -n flux-system
   flux get kustomizations -A
   ```

### Verify Recovery

```bash
ssh kagiso@10.0.10.10
flux get kustomizations -A
flux get helmreleases -A
# SUSPENDED column should show False for all resources
```

---

## TraefikHighErrorRate

| Field | Value |
|-------|-------|
| Severity | Warning |
| Threshold | HTTP 5xx error rate > 5% over 5 minutes |
| First Response | 15 minutes |

### What This Alert Means

Traefik (running at 10.0.10.110) is returning a high rate of 5xx errors to clients. This means upstream services are failing or Traefik itself is misconfigured. User-facing services may be degraded.

### Diagnostic Steps

1. Check Traefik pod status in the cluster:
   ```bash
   ssh kagiso@10.0.10.10
   kubectl get pods -n kube-system | grep traefik
   kubectl logs -n kube-system -l app.kubernetes.io/name=traefik --since=30m | grep -E "error|Error|level=error" | tail -30
   ```

2. Check which routes/services are generating errors from Traefik dashboard:
   ```bash
   # Traefik dashboard (if exposed):
   curl -s http://10.0.10.110:8080/api/http/routers | python3 -m json.tool | grep -E "name|status"
   ```

3. Check the actual services behind the failing routes:
   ```bash
   kubectl get ingressroute -A
   kubectl get ingress -A
   # For each affected service:
   kubectl get endpoints -n <namespace> <service-name>
   # No endpoints = backend pods are down
   ```

4. Check if the upstream pods are running:
   ```bash
   kubectl get pods -A | grep -v "Running\|Completed"
   ```

5. Check Traefik middleware configurations:
   ```bash
   kubectl get middleware -A
   kubectl describe middleware -n <namespace> <middleware-name>
   ```

6. Review Prometheus metrics for specific error breakdown:
   ```bash
   # Query: sum(rate(traefik_service_requests_total{code=~"5.."}[5m])) by (service)
   kubectl port-forward -n monitoring svc/prometheus-operated 9090:9090 &
   # Then open http://localhost:9090 in browser (via SSH tunnel)
   ```

### Decision Table

| Condition | Action |
|-----------|--------|
| No endpoints for service | Backend pods are down; check pod status |
| Traefik pod crashlooping | See [PodCrashLooping](#podcrashlooping) |
| All services failing | Check if Traefik has lost connectivity to cluster DNS |
| Specific service failing | Debug that service's pods and logs |
| TLS errors causing 5xx | Check certificate status; see [CertificateNotReady](#certificatenotready) |

### Verify Recovery

```bash
ssh kagiso@10.0.10.10
kubectl logs -n kube-system -l app.kubernetes.io/name=traefik --since=5m | grep -c "level=error"
# Error count should be near 0
# Also verify from Prometheus that 5xx rate has dropped
```

---

## TraefikHighLatency

| Field | Value |
|-------|-------|
| Severity | Warning |
| Threshold | p99 request latency > 2 seconds over 5 minutes |
| First Response | 30 minutes |

### What This Alert Means

Traefik is taking over 2 seconds to serve the 99th percentile of requests. This indicates slow upstream services, resource contention on the Traefik node, or network issues between Traefik and the backend pods.

### Diagnostic Steps

1. Check Traefik pod resource usage:
   ```bash
   ssh kagiso@10.0.10.10
   kubectl top pod -n kube-system -l app.kubernetes.io/name=traefik
   kubectl describe pod -n kube-system -l app.kubernetes.io/name=traefik | grep -A10 "Limits:\|Requests:"
   ```

2. Check which services have high latency using Traefik metrics:
   ```bash
   # Prometheus query: histogram_quantile(0.99, rate(traefik_service_request_duration_seconds_bucket[5m])) by (service)
   kubectl logs -n kube-system -l app.kubernetes.io/name=traefik --since=15m | grep -E "duration|slow" | tail -20
   ```

3. Check node resources on the control plane (10.0.10.11) where Traefik may run:
   ```bash
   kubectl top node
   ssh kagiso@10.0.10.11 "top -bn1 | head -20"
   ```

4. Check if NFS mounts are causing latency (NFS hangs cascade to all services using NFS-backed volumes):
   ```bash
   ssh kagiso@10.0.10.11  # or 12/13 depending on pod placement
   mount | grep nfs
   # Test NFS responsiveness:
   time ls /mnt/archive/
   ```

5. Check if TrueNAS is under load:
   ```bash
   ssh admin@10.0.10.80 "top -bn1 | head -10"
   ```

6. Check if specific pods have slow responses:
   ```bash
   for pod in $(kubectl get pods -A -o name); do
     kubectl top pod ${pod#*/} -n ${pod%%/*} 2>/dev/null
   done | sort -k3 -rn | head -10
   ```

### Decision Table

| Condition | Action |
|-----------|--------|
| NFS mount hanging | Check TrueNAS health; see [TrueNASDown](infrastructure-runbooks.md#truenasdown) |
| Traefik CPU throttled | Increase Traefik CPU limits in HelmRelease values |
| Specific service slow | Debug that service (app logs, DB queries, etc.) |
| All services slow | Check node-level resource exhaustion |
| High load on tywin | Review control plane pod scheduling |

### Verify Recovery

```bash
ssh kagiso@10.0.10.10
kubectl top nodes
# All nodes should show reasonable CPU/memory
# Also check Prometheus: p99 latency should drop below 2s
```
