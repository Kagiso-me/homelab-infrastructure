# Uptime SLA and Availability Targets

## Document Control

| Field        | Value             |
|--------------|-------------------|
| Version      | 1.0               |
| Date         | 2026-03-14        |
| Status       | Active            |
| Owner        | Platform Engineer |
| Review Cycle | Quarterly         |

---

## 1. Purpose and Classification

This document defines the availability targets and service level expectations for the homelab Kubernetes infrastructure.

> **Important Classification:** This is a self-hosted homelab environment operated by a single engineer on consumer-grade hardware. It is explicitly **not** a production SLA. The targets defined here are aspirational goals used for self-accountability and portfolio documentation purposes. No commercial, contractual, or external service level obligations exist.

There is no on-call rotation, no secondary operator, and no guaranteed response time. Downtime may occur without notice due to maintenance, hardware failure, power outages, or personal availability of the operator.

---

## 2. Availability Targets

Availability targets are defined per service tier. Actual availability is measured via uptime dashboards in Grafana, powered by the kube-prometheus-stack.

### 2.1 Service Tiers

| Tier   | Description                                    | Examples                                       |
|--------|------------------------------------------------|------------------------------------------------|
| Tier 1 | Core infrastructure (always required)          | Kubernetes API server, FluxCD, Ingress (Traefik), TLS, Monitoring |
| Tier 2 | Primary user-facing services                   | Self-hosted applications accessible via kagiso.me |
| Tier 3 | Non-critical / experimental workloads          | Dev/test deployments, experimental services    |

### 2.2 Availability Targets Table

| Tier   | Target Availability | Allowed Downtime (monthly) | Actual (YTD)                             |
|--------|---------------------|----------------------------|------------------------------------------|
| Tier 1 | 99.0%               | ~7.3 hours                 | TBD — monitored via Grafana uptime dashboards |
| Tier 2 | 98.0%               | ~14.4 hours                | TBD — monitored via Grafana uptime dashboards |
| Tier 3 | Best-effort         | No target                  | TBD — monitored via Grafana uptime dashboards |

> **Note:** These targets are measured excluding scheduled maintenance windows (see Section 4). The 99.0% target for Tier 1 equates to approximately 87.6 hours of allowed downtime per year — realistic for a single-operator homelab, even with an HA control-plane, because several stateful services still run as single instances.

### 2.3 Measurement Methodology

Availability is measured by:
- **Prometheus Blackbox Exporter** probing HTTP/HTTPS endpoints for Tier 2 services
- **kube-state-metrics** tracking pod readiness and node availability for Tier 1
- Grafana dashboards aggregate this data into uptime percentage calculations

Measurements are stored in the Prometheus TSDB with a retention period of 15 days (configurable). Long-term uptime trends are tracked via Grafana dashboard annotations.

---

## 3. Recovery Time and Recovery Point Objectives

These values are the same as defined in the Disaster Recovery Plan and are reproduced here for completeness.

| Scenario                          | RTO                 | RPO                                      |
|-----------------------------------|---------------------|------------------------------------------|
| Single node failure               | ~15–30 minutes      | Zero for stateless workloads; app-specific for single-instance stateful services |
| API VIP leader loss               | ~1–5 minutes        | Zero                                     |
| Full cluster rebuild              | ~90–120 minutes     | Up to 6h (etcd) / 24h (PV data)         |
| TrueNAS storage failure           | ~60 minutes         | Up to 24 hours (last Velero backup)      |

These are realistic estimates based on documented runbooks, not contractual commitments.

---

## 4. Maintenance Windows

Planned maintenance is conducted within the following scheduled window to minimise disruption:

| Window         | Day      | Time (SAST)  | Frequency | Impact                                  |
|----------------|----------|--------------|-----------|-----------------------------------------|
| Primary        | Sunday   | 02:00–04:00  | Weekly    | Potential service interruption          |
| Emergency      | Any      | As required  | Ad hoc    | Documented as unplanned downtime        |

**SAST = UTC+2 (South Africa Standard Time)**

During the maintenance window, the following activities may occur:
- k3s version upgrades (via system-upgrade-controller)
- Node OS patching and reboots
- Helm chart updates applied by Flux
- TrueNAS firmware or ZFS updates
- Certificate rotation and RBAC changes

Services impacted by maintenance within the defined window are **excluded from availability calculations**. Maintenance performed outside this window is counted as unplanned downtime unless pre-announced.

---

## 5. Incident Severity Classification

| Severity | Description                                                                   | Target Response    | Target Resolution |
|----------|-------------------------------------------------------------------------------|--------------------|-------------------|
| P1       | Complete cluster outage; all Tier 1 services unavailable                     | Best-effort, ASAP  | Within RTO (~2h)  |
| P2       | Tier 2 service(s) unavailable; cluster infrastructure functional             | Within 4 hours     | Within 24 hours   |
| P3       | Degraded performance, non-critical service unavailable, monitoring alert     | Within 24 hours    | Within 1 week     |

> **Note:** These are single-operator response targets. There is no pager, no on-call rotation, and no guaranteed response time outside of the operator's personal availability. A P1 occurring at 03:00 on a weekday will be addressed when the operator is available.

### 5.1 Incident Declaration

An incident is declared when:
- An Alertmanager notification fires for a Tier 1 or Tier 2 service
- The operator observes a service availability failure
- An end user reports a service degradation (informal; homelab has no formal user base)

Incidents are tracked informally in `docs/compliance/incident-log.md`.

---

## 6. Escalation Path

This is a single-operator environment. There is no escalation path beyond the Platform Engineer.

| Level      | Contact           | Scope                                    |
|------------|-------------------|------------------------------------------|
| Level 1    | Platform Engineer | All incidents; sole responder            |
| External   | Community forums  | k3s, TrueNAS, FluxCD community support  |
| External   | Vendor support    | Backblaze B2 (storage); GitHub (GitOps) |

The absence of an escalation path is an accepted operational risk in this homelab context. Community forums (Reddit, Discord, GitHub Issues) are the effective escalation path for complex infrastructure problems.

---

## 7. Exclusions

The following conditions are excluded from availability calculations and do not constitute SLA violations:

| Exclusion Category                 | Description                                                                 |
|------------------------------------|-----------------------------------------------------------------------------|
| Scheduled maintenance              | Downtime within the Sunday 02:00–04:00 SAST window                        |
| Upstream provider outages          | GitHub unavailability (Flux reads from GitHub); Let's Encrypt outages; Backblaze B2 outages |
| ISP / WAN outages                  | Internet connectivity failures affecting external access to kagiso.me      |
| Power outages                      | Unplanned power interruptions to homelab hardware                          |
| Hardware end-of-life failure       | Consumer hardware failure beyond normal expected lifespan                  |
| Force majeure                      | Natural disasters, acts of god, events outside operator control            |

---

## 8. Reporting and Review

Uptime data is available in real-time via Grafana dashboards. No formal SLA reports are generated. Availability trends are reviewed as part of the quarterly compliance review cycle.

This document is reviewed quarterly. Targets may be revised based on:
- Observed actual availability trends from Grafana
- Changes to infrastructure (adding HA control-plane, etc.)
- Changes to workload criticality

| Version | Date       | Author            | Summary of Changes     |
|---------|------------|-------------------|------------------------|
| 1.0     | 2026-03-14 | Platform Engineer | Initial document       |

