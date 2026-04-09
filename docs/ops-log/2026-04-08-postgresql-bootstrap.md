# 2026-04-08 — MAINTENANCE: PostgreSQL Bootstrap — Provision App Databases

**Operator:** Kagiso
**Type:** `MAINTENANCE`
**Components:** PostgreSQL (shared cluster) · authentik · vaultwarden · nextcloud · immich · n8n
**Commit:** —
**Downtime:** ~2h (apps in CrashLoopBackOff until databases provisioned)

---

## What Changed

Manually provisioned PostgreSQL users, databases, and extensions for all apps that use the
shared cluster PostgreSQL. This is a one-time bootstrap step required whenever the PostgreSQL
PV is recreated from scratch.

---

## Why

The shared PostgreSQL instance (`postgresql-primary` in `databases` namespace) was a fresh
install with an empty data directory. All apps were configured to connect to external PostgreSQL
(bundled PostgreSQL disabled in their Helm charts), but none of their users or databases existed.
Every app was crash-looping with `FATAL: password authentication failed`.

---

## Commands Run

```bash
KUBECONFIG=/etc/rancher/k3s/k3s.yaml kubectl exec -n databases postgresql-primary-0 -- psql -U postgres
```

```sql
-- authentik
CREATE USER authentik WITH PASSWORD '<from authentik-secret: postgresql-password>';
CREATE DATABASE authentik OWNER authentik;

-- vaultwarden
CREATE USER vaultwarden WITH PASSWORD '<from vaultwarden-secret: db-password>';
CREATE DATABASE vaultwarden OWNER vaultwarden;

-- nextcloud
CREATE USER nextcloud WITH PASSWORD '<from nextcloud-secret: postgresql-password>';
CREATE DATABASE nextcloud OWNER nextcloud;

-- immich
CREATE USER immich WITH PASSWORD '<from immich-secret: db-password>';
CREATE DATABASE immich OWNER immich;

-- n8n
CREATE USER n8n WITH PASSWORD '<from n8n-secret: db-password>';
CREATE DATABASE n8n OWNER n8n;
```

Immich also requires several PostgreSQL extensions that must be created as superuser before
first startup (the `immich` user lacks `CREATE EXTENSION` privileges):

```sql
-- Run against the immich database as postgres superuser
\c immich
CREATE EXTENSION IF NOT EXISTS vector;        -- pgvector (similarity search)
CREATE EXTENSION IF NOT EXISTS cube;          -- required by earthdistance
CREATE EXTENSION IF NOT EXISTS earthdistance; -- geo distance queries
CREATE EXTENSION IF NOT EXISTS unaccent;      -- accent-insensitive search
CREATE EXTENSION IF NOT EXISTS pg_trgm;       -- fuzzy text search
```

---

## Secrets Reference

All passwords are stored in Kubernetes secrets — never hardcoded. To retrieve:

```bash
kubectl get secret <secret-name> -n <namespace> -o jsonpath='{.data.<key>}' | base64 -d
```

| App        | Namespace | Secret name        | Key                   |
|------------|-----------|--------------------|-----------------------|
| authentik  | auth      | authentik-secret   | postgresql-password   |
| vaultwarden| apps      | vaultwarden-secret | db-password           |
| nextcloud  | apps      | nextcloud-secret   | postgresql-password   |
| immich     | apps      | immich-secret      | db-password           |
| n8n        | apps      | n8n-secret         | db-password           |

---

## Outcome

- All 5 app databases created ✓
- All 5 app users created with correct passwords ✓
- Immich pgvector + earthdistance + unaccent + pg_trgm extensions created ✓
- authentik: `Ready: True` ✓
- vaultwarden: `1/1 Running` ✓
- immich-server: `1/1 Running` ✓
- n8n: `1/1 Running` ✓
- nextcloud: initializing (first-boot migrations)

---

## If This Happens Again

Run the SQL block above. All passwords come from the Kubernetes secrets — retrieve them
first, then substitute. The Immich extensions must always be created before Immich starts
for the first time against a new database.

For convenience, consider scripting this as a Kubernetes Job that runs once on PostgreSQL
first-boot (via an init hook or a post-install Helm hook).

---

## Related

- Shared PostgreSQL HelmRelease: `platform/databases/postgresql/helmrelease.yaml`
- App secrets: `platform/security/authentik/`, `apps/*/` (SOPS-encrypted)
