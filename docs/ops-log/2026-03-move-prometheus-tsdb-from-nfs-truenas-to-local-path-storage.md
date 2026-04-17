# 2026-03 — FIX: Move Prometheus TSDB from nfs-truenas to local-path storage

**Operator:** Kagiso
**Type:** `FIX`
**Components:** Prometheus · TrueNAS NFS · local-path-provisioner
**Commit:** —
**Downtime:** None (rolling PV migration)

---

## What Changed

Moved Prometheus's TSDB (time-series database) PersistentVolume from the `nfs-truenas` StorageClass to `local-path` (node-local disk on `tywin`). Removed the `--storage.tsdb.no-lockfile` flag that was previously required as an NFS workaround.

---

## Why

NFS and Prometheus's TSDB are fundamentally incompatible at anything above toy scale. Any brief network hiccup or TrueNAS blip causes the NFS mount to return "stale NFS file handle" errors. Prometheus silently drops all incoming metrics while continuing to show scrape targets as healthy — no alerts fire, no errors surface, and you only notice when you look at a graph and the data just stops. The `--no-lockfile` flag papered over a symptom without fixing the root cause.

Grafana and Alertmanager remain on NFS because they are low write-frequency and don't suffer the same sensitivity to mount interruptions.

---

## Details

- New PV: `local-path` on `tywin`, 20Gi
- Old PV: `nfs-truenas`, retained and manually deleted after migration
- Removed flag: `--storage.tsdb.no-lockfile` from Prometheus args
- ADR written: [ADR-009](docs/adr/ADR-009-prometheus-local-storage.md)
- Prometheus pod restarted cleanly, TSDB lock acquired correctly

---

## Outcome

- Prometheus TSDB now on local disk — no NFS dependency for metrics writes ✓
- `--storage.tsdb.no-lockfile` removed — lock file works correctly ✓
- No metric gaps observed after migration ✓
- Grafana and Alertmanager unaffected ✓

---

## Rollback

```bash
# Revert HelmRelease values to nfs-truenas storageClass and add --no-lockfile arg back
# Not recommended — root cause is NFS incompatibility, not configuration
```

---

## Related

- ADR-009: Prometheus Local Storage — `docs/adr/ADR-009-prometheus-local-storage.md`
