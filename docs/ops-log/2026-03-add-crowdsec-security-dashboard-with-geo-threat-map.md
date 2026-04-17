# 2026-03 — DEPLOY: Add CrowdSec security dashboard with geo threat map

**Operator:** Kagiso
**Type:** `DEPLOY`
**Components:** CrowdSec · Grafana · Prometheus · geo threat map
**Commit:** —
**Downtime:** None

---

## What Changed

Added the CrowdSec Grafana dashboard from the CrowdSec hub, extended with a world map panel showing attack origin countries using Grafana's geomap visualisation.

---

## Why

CrowdSec was blocking IPs but the only way to see what was happening was `cscli decisions list` in the terminal. A dashboard makes the threat landscape visible — you can see which countries are actively probing, how many unique IPs have been banned, and whether the block rate is growing (indicating an active campaign) or stable (background noise).

The geo map is primarily informational but also useful for making manual GeoIP block decisions — if 95% of attacks come from a specific region and you have no users there, a Traefik GeoIP middleware is worth considering.

---

## Details

- **Base dashboard**: CrowdSec official Grafana dashboard (imported from CrowdSec hub, ID: 14284)
- **Added panels**:
  - World map (Grafana geomap plugin) with attack origins from CrowdSec parsed logs
  - Ban rate over time (bans per hour)
  - Top 10 attacking IPs (last 24h)
  - Scenario breakdown (which detection rules are firing most)
- **Data source**: Prometheus metrics from `crowdsec-agent` + Loki log parsing for geo data
- **Loki integration**: CrowdSec access logs forwarded to Loki via Promtail, geo panel queries Loki LogQL

---

## Outcome

- CrowdSec dashboard deployed via ConfigMap ✓
- Geo threat map rendering with real data ✓
- Top attacking scenarios visible ✓

---

## Related

- CrowdSec HelmRelease: `platform/security/crowdsec/helmrelease.yaml`
- Dashboard: `platform/observability/grafana-dashboards/crowdsec.json`
