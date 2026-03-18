# TrueNAS — MinIO Configuration

MinIO provides an S3-compatible API on top of TrueNAS storage. Velero uses it as the backup target.

---

## Why MinIO

Velero's AWS plugin speaks S3. TrueNAS NFS does not. MinIO bridges this gap by exposing the underlying ZFS dataset through an S3 API. This also provides:

- bucket-level access control
- audit logging of backup operations
- compatibility with any S3-aware tool (AWS CLI, rclone, etc.)

---

## Architecture

```
Velero (in k3s cluster)
    │
    │  S3 API (port 9000)
    ▼
MinIO (TrueNAS App)
    │
    │  Host path
    ▼
/mnt/archive/backups/k8s/minio  (ZFS dataset)
    │
    ├── velero/              (bucket: velero)
    │   └── backups/...
    │
    └── (future buckets)
```

---

## MinIO App Settings

Deployed via TrueNAS Apps (TrueNAS SCALE built-in MinIO chart).

Navigate to: **Apps → Discover Apps → MinIO → Install**

| Setting | Value |
|---------|-------|
| Application Name | `minio` |
| Root User | `admin` |
| Root Password | *(generate strong password — store in password manager)* |
| Storage type | Host Path |
| Host Path | `/mnt/archive/backups/k8s/minio` |
| API Port | `9000` |
| Console Port | `9001` |
| Host Network | Enabled *(recommended — simpler networking)* |

---

## Access Points

| Interface | URL |
|-----------|-----|
| MinIO Console (web UI) | http://10.0.10.80:9001 |
| MinIO S3 API | http://10.0.10.80:9000 |

---

## Bucket Layout

| Bucket | Purpose |
|--------|---------|
| `velero` | Velero backup objects |

Create in MinIO Console: **Buckets → Create Bucket**

| Setting | Value |
|---------|-------|
| Bucket Name | `velero` |
| Versioning | Off |
| Object Locking | Off |

---

## Access Key for Velero

Velero uses a dedicated access key — never the root credentials.

Create in MinIO Console: **Access Keys → Create Access Key**

| Credential | Action |
|-----------|--------|
| Access Key ID | Copy — goes into the SOPS-encrypted Kubernetes Secret |
| Secret Access Key | Copy now — shown only once — save in password manager |

Store in the cluster Secret (see [Guide 08](../../docs/guides/08-Cluster-Backups.md) — Step 5):

```bash
sops platform/backup/velero/minio-credentials.yaml
```

---

## Verifying MinIO

From any cluster node:

```bash
curl -I http://10.0.10.80:9000/minio/health/live
# Expected: HTTP/1.1 200 OK
```

From the Velero CLI (on the RPi):

```bash
velero backup-location get
# Expected phase: Available
```

---

## Capacity Planning

Velero backup sizes depend on PVC data. With 7-day retention and daily backups:

```
Estimated storage = (average backup size) × 7
```

For a typical homelab with 5–10 PVCs:

- Small PVCs (config only): 50–200 MB per backup
- Medium PVCs (Prometheus TSDB): 1–5 GB per backup

Monitor in MinIO Console: **Buckets → velero → Summary** shows total object size.

---

## Troubleshooting

**Velero backup-location phase: Unavailable**

```bash
velero backup-location get truenas-minio -o yaml
# Look at status.message
```

Common causes:
- MinIO app not running in TrueNAS Apps
- Endpoint URL wrong in Velero HelmRelease (`http://10.0.10.80:9000`)
- Bucket `velero` does not exist
- Credentials in `velero-minio-credentials` Secret are incorrect

**Verify credentials directly:**

```bash
# Install AWS CLI on RPi
pip3 install awscli

# Test with MinIO endpoint
AWS_ACCESS_KEY_ID=<key> AWS_SECRET_ACCESS_KEY=<secret> \
  aws s3 ls s3://velero --endpoint-url=http://10.0.10.80:9000
```
