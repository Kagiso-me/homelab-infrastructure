# 2026-03 — DEPLOY: Add latency and resource panels to database dashboards

**Operator:** Kagiso
**Type:** `DEPLOY`
**Components:** Grafana · PostgreSQL · Redis · prometheus-postgres-exporter · prometheus-redis-exporter
**Commit:** —
**Downtime:** None

---

## What Changed

Extended the database Grafana dashboards with latency panels (query duration p50/p95/p99) and resource panels (connection pool usage, buffer cache hit rate for PostgreSQL; memory usage, keyspace hit rate for Redis).

---

## Why

The initial database dashboards showed only whether the pods were up. When apps were slow, there was no way to tell if the bottleneck was database query latency, connection pool exhaustion, or something else. These panels make database performance problems diagnosable from Grafana rather than requiring a psql session and `pg_stat_activity` queries.

---

## Details

**PostgreSQL panels added** (via `prometheus-postgres-exporter` metrics):
- Query duration p50 / p95 / p99 (from `pg_stat_statements`)
- Active connections / max connections utilisation %
- Buffer cache hit rate (should be > 99% for a well-tuned instance)
- Table bloat by database
- WAL write rate

**Redis panels added** (via `prometheus-redis-exporter` metrics):
- Memory used / maxmemory %
- Keyspace hit rate
- Commands per second by type
- Connected clients
- Evicted keys rate

---

## Outcome

- Database dashboards show meaningful performance metrics ✓
- First use: identified PostgreSQL connection pool at 85% during Immich ML backfill — increased `max_connections` ✓

---

## Related

- postgres-exporter: `platform/observability/exporters/postgres-exporter.yaml`
- redis-exporter: `platform/observability/exporters/redis-exporter.yaml`
