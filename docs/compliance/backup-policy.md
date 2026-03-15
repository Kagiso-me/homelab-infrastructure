# Backup Policy

## Document Control

| Field        | Value             |
|--------------|-------------------|
| Version      | 1.0               |
| Date         | 2026-03-14        |
| Status       | Active            |
| Owner        | Platform Engineer |
| Review Cycle | Quarterly         |

---

## 1. Purpose and Scope

This policy defines the backup requirements, schedule, retention, and verification procedures for the homelab Kubernetes infrastructure. It ensures that sufficient data protection measures are in place to meet the recovery objectives defined in the Disaster Recovery Plan.

**In scope:**
- Kubernetes cluster state (etcd)
- Persistent Volume data (NFS-backed PVCs)
- TrueNAS storage datasets (NFS exports, MinIO bucket)
- Configuration and secrets managed via GitOps (FluxCD)

**Out of scope:**
- `flux-system` namespace (cluster state is in Git; bootstrapping re-creates this namespace)
- `kube-system` namespace (restored via etcd snapshot or k3s reinstall)
- Ephemeral workloads with no persistent volumes
- External services (GitHub, Backblaze B2 platform itself)

---

## 2. Backup Tiers

The backup strategy is composed of four distinct tiers providing defense-in-depth.

| Tier | Label              | Mechanism                    | Destination              | Schedule                | Retention       |
|------|--------------------|------------------------------|--------------------------|-------------------------|-----------------|
| L1   | etcd Snapshots     | k3s built-in snapshot        | TrueNAS NFS (10.0.10.80)  | Every 6 hours           | 5 snapshots     |
| L2   | Velero Backups     | Velero + Restic/Kopia        | MinIO on TrueNAS         | Daily at 03:00          | 30 days         |
| L3   | ZFS Snapshots      | TrueNAS periodic snapshots   | Local ZFS pool           | Hourly / Daily          | 7d / 30d        |
| L4   | Offsite Cloud Sync | TrueNAS Cloud Sync           | Backblaze B2             | Nightly                 | 30 days minimum |

### Tier Details

#### L1 — etcd Snapshots

k3s is configured with embedded etcd. Automatic snapshots are taken every 6 hours and written to the TrueNAS NFS share mounted at `/var/lib/rancher/k3s/server/db/snapshots/` (or equivalent NFS path). The 5 most recent snapshots are retained; older snapshots are pruned automatically.

etcd snapshots capture full Kubernetes API state: all objects, namespaces, RBAC bindings, Secrets (encrypted at rest), ConfigMaps, and CRD instances. They do not capture PVC data.

#### L2 — Velero Application Backups

Velero runs as a cluster deployment with the Restic or Kopia integration enabled for filesystem-level PVC backup. A scheduled CronJob triggers daily at 03:00.

- All namespaces are included by default, with explicit exclusions (see Section 5).
- Backup objects (metadata + PVC data) are stored in the MinIO S3-compatible bucket on TrueNAS.
- Velero backups include: Kubernetes resource manifests, PVC data snapshots, Namespace metadata.
- TTL is set to 720 hours (30 days). Velero automatically deletes expired backups and their associated object storage data.

#### L3 — TrueNAS ZFS Snapshots

TrueNAS is configured with periodic snapshot tasks on all relevant datasets:
- **Hourly snapshots** retained for 7 days (captures NFS dataset state including PVC data and MinIO bucket)
- **Daily snapshots** retained for 30 days

ZFS snapshots are space-efficient copy-on-write snapshots. They protect against accidental data deletion, corruption, and NFS-layer issues independently of the Velero backup schedule.

#### L4 — Backblaze B2 Cloud Sync

TrueNAS Cloud Sync tasks replicate critical datasets to a Backblaze B2 bucket nightly. This provides offsite protection against hardware failure of the NAS itself.

Synced datasets include:
- etcd snapshot NFS share
- MinIO bucket dataset (Velero backup data)

---

## 3. Retention Schedule

| Data Type             | Minimum Retention | Maximum Retention | Notes                                   |
|-----------------------|-------------------|-------------------|-----------------------------------------|
| etcd snapshots        | 1 day (5 copies)  | ~1.25 days        | Rolling window; 5 snapshots at 6h each |
| Velero backups        | 30 days           | 30 days           | Configurable via TTL in Schedule object |
| ZFS hourly snapshots  | 7 days            | 7 days            | Auto-pruned by TrueNAS                  |
| ZFS daily snapshots   | 30 days           | 30 days           | Auto-pruned by TrueNAS                  |
| Backblaze B2          | 30 days           | Indefinite        | Subject to B2 bucket lifecycle policy   |

Retention periods are reviewed quarterly and may be adjusted based on available storage capacity.

---

## 4. Encryption at Rest

All backup data is encrypted at rest using the following mechanisms:

| Layer           | Encryption Method                                        |
|-----------------|----------------------------------------------------------|
| etcd snapshots  | etcd encryption at rest (k3s EncryptionConfiguration)   |
| Velero backups  | MinIO server-side encryption; Restic repo encryption     |
| ZFS pool        | ZFS native encryption on TrueNAS pool                    |
| Backblaze B2    | Server-side encryption (AES-256); transfer via HTTPS/TLS |
| Git secrets     | SOPS + age encryption; no plaintext secrets in repo      |

Encryption keys (age private key, Restic repository password, MinIO credentials) are stored in a password manager external to the cluster and are not committed to the Git repository in plaintext.

---

## 5. Backup Exclusions

The following are explicitly excluded from Velero application backups:

| Namespace / Resource    | Reason for Exclusion                                                       |
|-------------------------|----------------------------------------------------------------------------|
| `flux-system`           | Flux state is authoritative in Git; re-bootstrapping restores this fully   |
| `kube-system`           | Restored via etcd snapshot or fresh k3s install; not safe to Velero-restore|
| `kube-public`           | Auto-generated; no user data                                               |
| `kube-node-lease`       | Auto-generated; no user data                                               |
| Ephemeral pods/jobs     | No persistent state; restored by Flux reconciliation                        |

Namespaces with the label `velero.io/exclude-from-backup: "true"` will be excluded from all Velero backups.

---

## 6. Access Controls

| Backup Tier       | Access Control                                                                     |
|-------------------|------------------------------------------------------------------------------------|
| etcd snapshots    | NFS mount accessible only from cluster nodes; TrueNAS dataset permissions restricted |
| Velero / MinIO    | MinIO credentials stored as SOPS-encrypted Kubernetes Secret; least-privilege bucket policy |
| ZFS snapshots     | Accessible only via TrueNAS UI/API; TrueNAS admin credentials in password manager |
| Backblaze B2      | Dedicated application key scoped to backup bucket; credentials in password manager |

No backup credentials are stored in plaintext in the Git repository or on cluster nodes.

---

## 7. Backup Monitoring

Backup health is monitored via the following mechanisms:

### Velero Metrics

Velero exposes Prometheus metrics including:
- `velero_backup_success_total` — count of successful backups
- `velero_backup_failure_total` — count of failed backups
- `velero_backup_last_successful_timestamp` — last successful backup time

These metrics are scraped by the kube-prometheus-stack Prometheus instance. Alertmanager rules are configured to fire if:
- No successful Velero backup has completed within the last 25 hours
- Any Velero backup reports a failure status

### etcd Snapshot Monitoring

k3s emits events and logs when etcd snapshots succeed or fail. A Prometheus/Loki alert is configured to notify if no snapshot is observed within a 7-hour window.

### ZFS and B2 Monitoring

TrueNAS SMART and pool health alerts are configured via TrueNAS email notifications. Backblaze B2 sync task results are monitored via TrueNAS Cloud Sync task history.

All alerts are routed via Alertmanager to the configured notification channel (email or messaging platform).

---

## 8. Restoration Testing Requirements

Backup data that has not been tested for restorability cannot be considered a reliable backup. The following restoration tests must be performed on the schedule defined in the Disaster Recovery Plan:

| Test                                  | Frequency   | Acceptance Criteria                                          |
|---------------------------------------|-------------|--------------------------------------------------------------|
| Velero single-namespace restore       | Quarterly   | Namespace and PVCs restored; application functional          |
| etcd snapshot restore (test cluster)  | Quarterly   | Cluster state matches snapshot; all objects present          |
| ZFS snapshot file-level restore       | Quarterly   | File restored from snapshot matches original                 |
| Backblaze B2 download and restore     | Quarterly   | Data downloaded successfully; integrity verified             |

Results are recorded in `docs/compliance/dr-test-log.md`.

---

## 9. Policy Compliance and Review

This policy is reviewed quarterly and after any significant change to the backup infrastructure. Non-compliance with backup schedules (e.g., missed backups reported by Alertmanager) must be investigated and remediated within 24 hours of detection.

Exceptions to this policy require documentation of the rationale and a compensating control.

| Version | Date       | Author            | Summary of Changes |
|---------|------------|-------------------|--------------------|
| 1.0     | 2026-03-14 | Platform Engineer | Initial document   |
