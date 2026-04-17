# 2026-03 — FIX: Scope promotion pipeline pod health checks to Flux-managed namespaces

**Operator:** Kagiso
**Type:** `FIX`
**Components:** GitHub Actions · promotion pipeline · Flux · system-upgrade-controller
**Commit:** —
**Downtime:** None

---

## What Changed

Updated the promotion pipeline's pod health check to scope kubectl queries to Flux-managed namespaces only, instead of running a cluster-wide `kubectl get pods -A` check.

---

## Why

The pipeline was checking `kubectl get pods -A --field-selector=status.phase!=Running` before promoting staging → prod. This worked fine until `system-upgrade-controller` started crash-looping in the `system-upgrade` namespace — a completely unrelated component being tested. The pipeline blocked promotion every time, even when all application workloads were healthy. A cluster-wide check conflates "is my app healthy" with "is every pod in the cluster healthy", which is not a useful gate.

---

## Details

- Namespaces now checked: `apps`, `auth`, `databases`, `media`, `monitoring`, `platform`
- Excluded: `kube-system`, `flux-system`, `system-upgrade`, `cert-manager` (infrastructure namespaces — not gated by app promotion)
- Check logic: `kubectl get pods -n <ns>` for each managed namespace, fail if any non-Running/Completed pod found
- system-upgrade-controller crash loop had no impact on subsequent promotion runs after fix

---

## Outcome

- Promotion pipeline unblocked ✓
- Health check now correctly reflects application workload health ✓
- system-upgrade-controller issues can be investigated independently ✓

---

## Rollback

Revert the namespace list in the promotion workflow YAML.

---

## Related

- Promotion pipeline: `.github/workflows/promote.yml`
