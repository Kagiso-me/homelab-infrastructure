# Disaster Recovery Plan

## Document Control

| Field       | Value                  |
|-------------|------------------------|
| Version     | 1.0                    |
| Date        | 2026-03-14             |
| Status      | Active                 |
| Owner       | Platform Engineer      |
| Review Cycle| Quarterly              |

---

## 1. Purpose and Scope

This Disaster Recovery Plan (DRP) defines the procedures, responsibilities, and objectives for recovering the homelab Kubernetes infrastructure following a disruptive event. It covers the k3s cluster, persistent workloads, GitOps pipeline, and supporting storage infrastructure.

**In scope:**
- k3s cluster nodes (tywin, jaime, tyrion)
- Persistent volume data hosted on TrueNAS NFS (10.0.10.80)
- FluxCD GitOps pipeline and configuration state (github.com/\<user\>/homelab-infrastructure)
- Monitoring stack (kube-prometheus-stack, Loki)
- Ingress and TLS infrastructure (Traefik, cert-manager, Let's Encrypt)

**Out of scope:**
- End-user devices and personal workstations
- External DNS provider (Cloudflare or equivalent) beyond configuration restore
- Upstream cloud services (Backblaze B2) — treated as a recovery destination, not a subject of recovery

---

## 2. Recovery Objectives

| Scenario                          | Recovery Time Objective (RTO) | Recovery Point Objective (RPO)        |
|-----------------------------------|-------------------------------|---------------------------------------|
| Single worker node failure        | ~30 minutes                   | Zero (workloads reschedule)           |
| Control-plane (tywin) failure     | ~60–90 minutes                | Up to 6 hours (last etcd snapshot)   |
| Full cluster loss (all nodes)     | ~90–120 minutes               | Up to 6 hours (etcd) / 24 hours (PV) |
| TrueNAS storage failure           | ~60 minutes (ZFS restore)     | Up to 24 hours (Velero snapshot)      |
| GitOps repository loss            | Near-zero (GitHub hosted)     | Near-zero (mirrored to remote)        |

> **Note:** RPO for persistent volume data is bounded by the Velero backup schedule (daily at 03:00). etcd snapshots run every 6 hours and capture cluster state only, not application data. Maximum data loss for PV-backed workloads is therefore up to 24 hours.

---

## 3. Backup Architecture

Recovery depends on a four-layer backup architecture providing defense in depth.

### Layer 1 — etcd Snapshots (Cluster State)

- **Mechanism:** k3s built-in etcd snapshot, scheduled every 6 hours
- **Destination:** NFS mount on TrueNAS (10.0.10.80)
- **Retention:** 5 snapshots retained
- **Scope:** Full Kubernetes cluster state (objects, RBAC, secrets, CRDs)
- **Runbook:** [`docs/operations/runbooks/restore-etcd.md`](../operations/runbooks/restore-etcd.md)

### Layer 2 — Velero Application Backups (Workload + PVC Data)

- **Mechanism:** Velero with Restic/Kopia filesystem backup
- **Destination:** MinIO instance on TrueNAS
- **Schedule:** Daily at 03:00 (full backup)
- **Retention:** 30 days
- **Scope:** All namespaces except `flux-system` and `kube-system` (see Backup Policy)
- **Runbook:** [`docs/operations/runbooks/backup-restoration.md`](../operations/runbooks/backup-restoration.md)

### Layer 3 — TrueNAS ZFS Snapshots (Storage Layer)

- **Mechanism:** TrueNAS periodic ZFS snapshot tasks
- **Destination:** Local ZFS pool on TrueNAS
- **Schedule:** Hourly snapshots, retained for 7 days; daily snapshots retained for 30 days
- **Scope:** All NFS datasets backing Kubernetes PVCs and MinIO data
- **Runbook:** [`docs/operations/runbooks/restore-zfs-snapshot.md`](../operations/runbooks/restore-zfs-snapshot.md)

### Layer 4 — Backblaze B2 Cloud Sync (Offsite)

- **Mechanism:** TrueNAS Cloud Sync task to Backblaze B2
- **Schedule:** Nightly
- **Scope:** Critical ZFS datasets (etcd snapshots, Velero MinIO bucket)
- **Retention:** Governed by B2 bucket lifecycle rules (minimum 30 days recommended)
- **Runbook:** [`docs/operations/runbooks/restore-from-b2.md`](../operations/runbooks/restore-from-b2.md)

---

## 4. Recovery Procedures Summary

Detailed step-by-step procedures are maintained in the [`docs/operations/runbooks/`](../operations/runbooks/) directory. This section summarises the recovery paths.

### 4.1 Single Worker Node Failure (jaime or tyrion)

1. Kubernetes will automatically reschedule pods to the remaining worker within minutes.
2. If the node requires rebuild: provision the host OS, install k3s agent, and join the cluster using the stored join token.
3. Verify node status: `kubectl get nodes`.
4. No data recovery is required for stateless workloads. For PVC-bound workloads, verify volume reattachment.
5. **Estimated RTO:** ~30 minutes.

**Runbook:** [`docs/operations/runbooks/node-replacement.md`](../operations/runbooks/node-replacement.md)

### 4.2 Control-Plane Node Failure (tywin)

1. Provision replacement host with identical hostname and IP (10.0.10.11) where possible.
2. Install k3s server with `--cluster-init` and restore the most recent etcd snapshot.
3. Verify all control-plane components are healthy: `kubectl get pods -n kube-system`.
4. Re-join worker nodes if cluster token changed.
5. Verify FluxCD reconciliation resumes: `flux get all`.
6. **Estimated RTO:** ~60–90 minutes.

**Runbook:** [`docs/operations/runbooks/cluster-rebuild.md`](../operations/runbooks/cluster-rebuild.md)

### 4.3 Full Cluster Rebuild

1. Restore TrueNAS from ZFS snapshot or Backblaze B2 if storage is also affected.
2. Provision all three nodes (tywin, jaime, tyrion) with base OS.
3. Bootstrap k3s control-plane on tywin and restore etcd snapshot.
4. Re-join jaime and tyrion as workers.
5. Bootstrap FluxCD: `flux bootstrap github` — Flux will reconcile the full cluster state from Git.
6. Restore PVC data from most recent Velero backup for stateful workloads.
7. Validate ingress, TLS certificates, and monitoring stack.
8. **Estimated RTO:** ~90–120 minutes.

**Runbook:** [`docs/operations/runbooks/cluster-rebuild.md`](../operations/runbooks/cluster-rebuild.md)

### 4.4 Storage (TrueNAS) Failure

1. If pool is intact: restore dataset from ZFS snapshot via TrueNAS UI.
2. If TrueNAS hardware has failed: restore from Backblaze B2 to a replacement NAS, then re-configure NFS exports.
3. Update NFS server IP in Kubernetes StorageClass if it has changed.
4. Verify PVC mounts: `kubectl get pvc -A`.
5. **Estimated RTO:** ~60 minutes (ZFS restore) or longer for hardware replacement.

**Runbook:** [`docs/operations/runbooks/restore-truenas-storage.md`](../operations/runbooks/restore-truenas-storage.md)

---

## 5. Roles and Responsibilities

This is a single-operator homelab environment. The following responsibilities are assigned to the Platform Engineer role.

| Responsibility                          | Role              |
|-----------------------------------------|-------------------|
| Declare disaster / initiate recovery    | Platform Engineer |
| Execute recovery runbooks               | Platform Engineer |
| Validate post-recovery state            | Platform Engineer |
| Update DR documentation and runbooks    | Platform Engineer |
| Conduct quarterly DR tests              | Platform Engineer |
| Maintain backup infrastructure          | Platform Engineer |

> **Note:** There is no on-call rotation or secondary responder. This is an accepted risk documented in ADR-005. Recovery procedures are documented sufficiently to allow a technically capable third party to execute them from the runbooks alone.

---

## 6. Test Schedule

Disaster recovery procedures must be tested on a quarterly basis to validate runbook accuracy and meet recovery objectives.

| Test Type                          | Frequency   | Last Tested | Next Due    |
|------------------------------------|-------------|-------------|-------------|
| Velero restore (single namespace)  | Quarterly   | TBD         | TBD         |
| etcd snapshot restore (test node)  | Quarterly   | TBD         | TBD         |
| ZFS snapshot restore (single file) | Quarterly   | TBD         | TBD         |
| Full worker node rebuild           | Semi-annual | TBD         | TBD         |
| Full cluster rebuild (tabletop)    | Annual      | TBD         | TBD         |
| Backblaze B2 restore validation    | Quarterly   | TBD         | TBD         |

Test results must be recorded in `docs/compliance/dr-test-log.md` including: date, scenario tested, RTO achieved, issues found, and remediation actions.

---

## 7. Contact Information

| Role              | Contact             | Availability          |
|-------------------|---------------------|-----------------------|
| Platform Engineer | Kagiso Tjeane       | Best-effort, homelab  |
| NAS Vendor Support| TrueNAS Community   | Community forums      |
| Cloud Storage     | Backblaze B2 Support| support.backblaze.com |

> This is a homelab environment. There is no SLA for response time and no external support contract.

---

## 8. Dependencies and Assumptions

- TrueNAS at 10.0.10.80 is operational and reachable over the storage VLAN.
- GitHub is available for Flux bootstrap. If GitHub is unavailable, cluster reconciliation will pause but existing workloads continue running.
- Backblaze B2 credentials are stored securely and accessible during a disaster. These credentials are encrypted via SOPS + age and stored in the Git repository.
- Node hostnames and IPs are stable and documented. DHCP reservations or static IP assignments are maintained at the network level.
- The age private key for SOPS decryption is stored out-of-band (e.g., password manager) and is not lost with the cluster.

---

## 9. Document Control and Review

This document must be reviewed:
- Quarterly, as part of the DR test cycle
- After any significant infrastructure change (new node, storage migration, etc.)
- After any actual recovery event, incorporating lessons learned

Change history is maintained in Git. The authoritative version of this document is the version in the `main` branch of the homelab-infrastructure repository.

| Version | Date       | Author            | Summary of Changes     |
|---------|------------|-------------------|------------------------|
| 1.0     | 2026-03-14 | Platform Engineer | Initial document       |
