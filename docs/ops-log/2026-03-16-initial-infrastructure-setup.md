# 2026-03-16 — DEPLOY: Initial Infrastructure Setup

**Operator:** Kagiso
**Type:** `DEPLOY`
**Components:** k3s · FluxCD v2 · SOPS/age · Prometheus · Grafana · Loki · Ansible
**Commit:** d8a66aa
**Downtime:** N/A (new build)

---

## What Changed

Stood up the entire homelab infrastructure from scratch. Three Lenovo ThinkCentre M93p nodes
provisioned as a k3s cluster, a Raspberry Pi 3B+ configured as the Ansible control hub, and
a full GitOps pipeline established using FluxCD v2 with SOPS-encrypted secrets.

---

## Why

Replacing an ad-hoc Docker-only setup with a proper Kubernetes-based homelab. Goals:
- GitOps-driven deployments — no more manual `docker run` commands
- Proper secret management via SOPS + age encryption
- Full observability stack from day one
- All infrastructure documented and reproducible

---

## Details

**Hardware provisioned:**
- `tywin` (10.0.10.11) — k3s control plane, ThinkCentre M93p, i5-4570T, 16GB DDR3, 256GB SSD
- `jaime` (10.0.10.12) — k3s worker, ThinkCentre M93p, i5-4570T, 16GB DDR3, 256GB SSD
- `tyrion` (10.0.10.13) — k3s worker, ThinkCentre M93p, i5-4570T, 16GB DDR3, 256GB SSD
- `rpi` (10.0.10.10) — Raspberry Pi 3B+, Ansible control hub
- `docker` (10.0.10.20) — Intel NUC NUC7i3BNH, Docker host (Prometheus, Grafana, Loki)
- `truenas` (10.0.10.80) — HP MicroServer Gen8, Xeon E31260L, 16GB ECC DDR3, NFS/S3 storage

**TrueNAS pool layout:**
- `core` — 2×480GB SSD mirror → k8s PVCs (NFS provisioner)
- `archive` — 2×4TB SAS mirror → backups (k3s, Docker, RPi, personal)
- `tera` — 1×8TB SAS single → media (movies, series, music)

**k3s cluster:**
- Provisioned via `ansible/playbooks/lifecycle/install-cluster.yml`
- k3s installed without default Traefik (replaced by standalone Traefik v3)
- Flannel CNI, etcd datastore (embedded)
- etcd snapshots directed to `archive/k8s-backups/etcd` via NFS

**FluxCD v2:**
- Bootstrapped against this repository
- SOPS + age encryption for all secrets
- Kustomize overlays per environment

**Monitoring stack (Docker host):**
- Prometheus scraping k3s nodes + TrueNAS via node-exporter and smartctl-exporter
- Grafana dashboards for cluster, node, and storage health
- Loki + Promtail for log aggregation
- Alertmanager with Slack webhook integration
- 55 alert rules across 4 files: kubernetes, backups, infrastructure, TrueNAS/SMART

**Documentation:**
- Guides 01–12 written covering every component
- Operational runbooks for all major failure scenarios
- ADRs documenting key architectural decisions
- Disaster recovery plan
- Alert runbooks for all 55 alert rules

---

## Outcome

- k3s cluster online with 1 control plane + 2 workers ✓
- FluxCD reconciling from GitHub ✓
- Monitoring stack collecting metrics and logs ✓
- All secrets encrypted at rest (SOPS/age) ✓
- Repository safe to push to public GitHub ✓

---

## Related

- Cluster install playbook: `ansible/playbooks/lifecycle/install-cluster.yml`
- Guide: `docs/guides/01-Home-Network-Setup.md`
- Guide: `docs/guides/02-TrueNAS-Storage.md`
- Architecture: `docs/architecture/cluster-architecture.md`
- Storage layout: `truenas/docs/dataset-layout.md`
