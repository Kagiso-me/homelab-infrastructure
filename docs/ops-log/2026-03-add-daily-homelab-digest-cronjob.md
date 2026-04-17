# 2026-03 — DEPLOY: Add daily homelab digest CronJob

**Operator:** Kagiso
**Type:** `DEPLOY`
**Components:** GitHub Actions · digest · CHANGELOG.md · ops-log
**Commit:** —
**Downtime:** None

---

## What Changed

Added the digest generation pipeline: a GitHub Actions workflow (`gen-digest.yml`) that parses `CHANGELOG.md` and ops-log markdown files to build `public/data/digest.json` for the site's ops feed.

---

## Why

The homelab site needed a way to surface infrastructure changes to visitors without manually maintaining a separate blog or feed. The CHANGELOG.md already tracked changes in a structured format (`- **[TYPE]** description → [details](link) \`commit\``). The digest pipeline reads that structure and converts it into the JSON that powers the `/digest` page.

---

## Details

- **Workflow**: `.github/workflows/gen-digest.yml` — runs hourly + on push to main
- **Script**: `scripts/gen-digest.sh` — parses CHANGELOG.md regex pattern, loads ops-log markdown body if file exists
- **Output**: `public/data/digest.json` — array of entries with slug, date, type, title, summary, commit, hasDetail flag, and optional body
- **Types surfaced**: DEPLOY, FIX, INCIDENT, HARDWARE, SECURITY, NETWORK (CONFIG/MAINTENANCE filtered unless they have a detail body)
- **Deduplication**: by slug, newest first
- **Commit**: workflow commits changes to `public/data/digest.json` if the file changed

---

## Outcome

- Digest pipeline running hourly ✓
- `/digest` page on site populated with real ops entries ✓
- Entries with ops-log files show full body on click-through ✓

---

## Related

- Workflow: `.github/workflows/gen-digest.yml`
- Script: `scripts/gen-digest.sh`
- Site digest page: `src/pages/digest.astro`
