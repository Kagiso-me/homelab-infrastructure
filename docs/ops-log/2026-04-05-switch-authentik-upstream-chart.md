# 2026-04-05 — DEPLOY: Switch authentik from custom chart to upstream official chart

**Operator:** Kagiso
**Type:** `DEPLOY`
**Components:** authentik · HelmRelease · HelmRepository · IngressRoute
**Commit:** <!-- fill after merge -->
**Downtime:** Partial — authentik was already broken (500 errors)

---

## What Changed

Replaced the in-house custom authentik Helm chart (`kagiso-me/authentik 0.1.0`) with the official upstream chart from `charts.goauthentik.io` version `2026.2.1`. Added a dedicated HelmRepository for the upstream chart. Reconfigured Redis connection from chart-level values to environment variables (`AUTHENTIK_REDIS__*`). Fixed IngressRoute service port from 9000 (container port) back to 80 (service port).

---

## Why

The custom in-house authentik chart had persistent 500 errors. The Go router's outpost controller was failing with "Failed to fetch outpost configuration — invalid header field value for Authorization". After extensive debugging (verifying database connectivity, TLS, Cloudflare tunnel routing, service ports), the root cause pointed to the custom chart's templating or configuration being fundamentally incompatible. The upstream chart is battle-tested, actively maintained by the authentik team, and is the recommended deployment method.

Additionally, a strategic decision was made: use upstream official charts where available (authentik, nextcloud), and only maintain custom charts for databases (PostgreSQL, Redis) where we want full control.

---

## Details

- **HelmRepository**: new `authentik` repo in `flux-system` namespace pointing to `https://charts.goauthentik.io`
- **Chart version**: `2026.2.1` (upstream) replaces `0.1.0` (custom)
- **PostgreSQL**: bundled bitnami postgres disabled (`postgresql.enabled: false`), still uses shared `postgresql-primary.databases.svc.cluster.local`
- **Redis**: no longer configured via `authentik.redis.*` values; now uses `AUTHENTIK_REDIS__HOST` and `AUTHENTIK_REDIS__PASSWORD` environment variables in `global.env`
- **Secrets**: same `authentik-secret` SOPS-encrypted secret, same keys — only the injection method for Redis changed
- **IngressRoute port fix**: PR #7 incorrectly changed port to 9000 (container port); reverted to 80 (service port as exposed by the upstream chart's server service)
- **Kustomization**: added `helmrepository.yaml` to resource list
- **PR**: #8

---

## Outcome

- [ ] Verified healthy
- [ ] No regressions observed
- [ ] Monitoring confirmed normal

---

## Rollback

```bash
# Revert to custom chart — restore previous HelmRelease pointing to kagiso-me repo
git revert <commit-hash>
git push
flux reconcile kustomization security --with-source
```

---

## Related

- PR #8: https://github.com/Kagiso-me/homelab-infrastructure/pull/8
- PR #7 (broke IngressRoute port): previously merged
- `platform/security/authentik/helmrelease.yaml`
- `platform/security/authentik/helmrepository.yaml`
- `platform/security/authentik/ingressroute.yaml`
- Upstream chart: https://charts.goauthentik.io
- Upstream docs: https://goauthentik.io/docs/
