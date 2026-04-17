# 2026-04 — DEPLOY: Pin image tags and configure Renovate for compose files

**Operator:** Kagiso
**Type:** `DEPLOY`
**Components:** Renovate · Docker Compose · varys · image tagging
**Commit:** —
**Downtime:** None

---

## What Changed

Pinned all Docker Compose service image tags to explicit versions (replacing `latest` and `:main` floating tags). Configured Renovate to monitor these Compose files and open PRs when new versions are available.

---

## Why

`latest` tags are a silent operational hazard. A `docker compose pull && docker compose up -d` on varys would silently upgrade every service to whatever "latest" meant that day — no changelog review, no testing, no rollback plan. Three times this led to unexpected breaking changes in services. Pinned tags make every version change explicit and deliberate.

Renovate provides the automation without losing control: it opens a PR with the new version, links to the changelog, and waits for manual approval before anything changes.

---

## Details

- **Files updated**: all `docker-compose.yml` files in `host-services/varys/`
- **Tag format**: explicit semver or digest where available (e.g. `ghcr.io/linuxserver/plex:1.40.2`, `ghcr.io/advplyr/audiobookshelf:2.9.0`)
- **Renovate config** (`renovate.json`):
  ```json
  {
    "extends": ["config:base"],
    "docker-compose": { "fileMatch": ["host-services/**/*.yml"] },
    "packageRules": [{ "matchDatasources": ["docker"], "automerge": false }]
  }
  ```
- Renovate running as GitHub App on the homelab-infrastructure repo
- First batch of PRs opened immediately after configuration, covering 8 services

---

## Outcome

- All Compose service images on pinned explicit versions ✓
- Renovate configured and opening update PRs ✓
- `latest` tag eliminated from all Compose files ✓
- No services broken during tag pinning ✓

---

## Related

- Renovate config: `renovate.json`
- Docker Compose files: `host-services/varys/`
