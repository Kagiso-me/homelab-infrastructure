# 2026-04 — DEPLOY: Add Seerr and cluster maintenance playbooks

**Operator:** Kagiso
**Type:** `DEPLOY`
**Components:** Seerr · Ansible · k3s cluster
**Commit:** —
**Downtime:** None

---

## What Changed

Deployed Seerr (media request management for Plex/Sonarr/Radarr) to the cluster. Also added Ansible playbooks for routine cluster maintenance: node drain/uncordon, etcd snapshot verification, and rolling k3s version upgrades.

---

## Why

Seerr replaces manual Sonarr/Radarr searches — users (just me, but still) can request movies and shows from a single UI that queues them into the right arr app. Without it, adding media requires logging into Sonarr or Radarr directly and knowing which one handles what.

The maintenance playbooks codify operations that were being done ad-hoc with one-liners. Having them in Ansible means they're repeatable, documented, and don't rely on remembering the right `kubectl` incantation at 11pm.

---

## Details

- **Seerr**: HelmRelease in `media` namespace, exposed at `requests.kagiso.me`, connected to Plex, Sonarr, and Radarr via API keys in SOPS secret
- **Maintenance playbooks added**:
  - `playbooks/drain-node.yml` — cordon + drain a node with grace period
  - `playbooks/verify-etcd-snapshot.yml` — check snapshot age and size on S3
  - `playbooks/upgrade-k3s.yml` — rolling upgrade via system-upgrade-controller plan

---

## Outcome

- Seerr running and connected to media stack ✓
- Media requests flowing through to Sonarr/Radarr ✓
- Maintenance playbooks tested on single node ✓

---

## Related

- Seerr HelmRelease: `apps/base/seerr/helmrelease.yaml`
- Ansible playbooks: `ansible/playbooks/`
