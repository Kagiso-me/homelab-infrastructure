
# Alert Runbook — PodCrashLoopBackOff

**Alert:** `KubePodCrashLooping`
**Severity:** Warning → Critical (based on restart count and pod criticality)
**First response time:** 15 minutes

---

## What This Alert Means

A pod is repeatedly crashing and Kubernetes is restarting it with exponential backoff. Common causes:

- Application error on startup (misconfiguration, missing dependency)
- OOMKilled — container exceeded its memory limit
- Readiness/liveness probe failure
- Missing or invalid Secret or ConfigMap
- Image pull failure (wrong tag, registry unreachable)

---

## Step 1 — Identify the pod

```bash
kubectl get pods -A | grep CrashLoopBackOff
```

Note the namespace and pod name.

---

## Step 2 — Check recent logs

```bash
# Current container output
kubectl logs <pod-name> -n <namespace>

# Previous (crashed) container output — usually more informative
kubectl logs <pod-name> -n <namespace> --previous
```

Look for the last lines before the crash. Application errors, panic traces, or `killed` messages appear here.

---

## Step 3 — Check pod events

```bash
kubectl describe pod <pod-name> -n <namespace>
```

Look at:
- `Events` — scheduling failures, image pull errors, probe failures
- `Last State` — exit code of the previous container (Exit Code 137 = OOMKilled, Exit Code 1 = application error)

---

## Step 4 — Determine root cause

| Exit Code | Meaning | Action |
|-----------|---------|--------|
| 0 | Clean exit (loop in start script) | Check entrypoint |
| 1 | Application error | Check logs |
| 137 | OOMKilled | Increase memory limit |
| 139 | Segfault | Likely a bug; check image version |
| 143 | SIGTERM | Pod was killed; check if probe timeout is too short |

---

## Step 5 — Common fixes

**OOMKilled:** Increase the memory limit in the HelmRelease values or Deployment spec. Commit the change to Git and let Flux apply it.

**Missing Secret:** Verify the referenced Secret exists in the correct namespace:
```bash
kubectl get secret <secret-name> -n <namespace>
```

If the Secret is SOPS-encrypted and missing, check that the `sops-age` Secret is present in `flux-system` and that Flux is correctly configured for decryption.

**Image pull failure:**
```bash
kubectl describe pod <pod-name> -n <namespace> | grep -A5 "Failed to pull"
```
Verify the image tag exists in the registry. Update the image reference in Git if incorrect.

**Liveness probe failing too aggressively:**
Check the probe configuration. If the application takes more than `initialDelaySeconds` to start, increase the delay:
```yaml
livenessProbe:
  initialDelaySeconds: 60  # increase if app is slow to start
```

---

## Step 6 — Verify recovery

```bash
kubectl get pods -n <namespace> --watch
```

Wait for the pod to show `Running` with restarts stable.

---

## Escalation

If the pod continues crashing after 3 fix attempts, check:
1. Whether the same pod was crashing before the incident (check Grafana restart rate panel)
2. Whether a recent Git commit changed the affected Deployment or its dependencies
3. Whether there is a Helm chart upgrade in progress (`flux get helmreleases -A`)

Roll back the most recent change via `git revert` if a deployment change is suspected.
