# 2026-03 — DEPLOY: Add ops-log, staging environment, and GitOps promotion pipeline

**Operator:** Kagiso
**Type:** `DEPLOY`
**Components:** GitHub Actions · Flux · staging · production · promotion pipeline
**Commit:** —
**Downtime:** None

---

## What Changed

Three related pieces shipped together:
1. **Ops-log**: the `docs/ops-log/` directory and template — structured records of every infrastructure change
2. **Staging environment**: a second Flux kustomization path (`apps/staging/`) that applies changes to a staging namespace before production
3. **Promotion pipeline**: GitHub Actions workflow that runs health checks and promotes staging → prod after manual approval

---

## Why

**Ops-log:** Changes were being made without any record of what changed, when, and why. After the third time debugging an issue that turned out to be caused by a change made two weeks prior, the ops-log became non-negotiable. Every change gets an entry. The template forces the right questions: what changed, why, what was the outcome.

**Staging + promotion:** Applying Flux changes directly to production meant every typo, misconfigured value, or broken image tag hit live services immediately. Staging provides a safe test surface. The promotion pipeline adds a human gate — changes don't reach prod without a passing health check and a deliberate merge.

---

## Details

- **Ops-log template**: `docs/ops-log/template.md` — operator, type, components, commit, downtime, what changed, why, details, outcome, rollback, related
- **Staging kustomization**: `apps/staging/kustomization.yaml` — mirrors prod but with reduced replicas and different image tag policy
- **Promotion workflow** (`.github/workflows/promote.yml`):
  1. Triggered on PR to `main`
  2. Checks pod health in Flux-managed namespaces
  3. Requires manual approval via GitHub environment protection rule
  4. Merges to `main` → Flux reconciles prod
- **Branch protection**: `main` protected, requires passing promotion workflow

---

## Outcome

- Ops-log template in place, first entries written ✓
- Staging environment reconciling changes before prod ✓
- Promotion pipeline running on all PRs ✓
- No direct pushes to main without pipeline ✓

---

## Related

- Promotion workflow: `.github/workflows/promote.yml`
- Staging kustomization: `apps/staging/kustomization.yaml`
- Ops-log template: `docs/ops-log/template.md`
