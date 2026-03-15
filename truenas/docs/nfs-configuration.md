# TrueNAS — NFS Configuration

NFS exports provide persistent storage to the Kubernetes cluster via the NFS subdir external provisioner.

---

## Required NFS Shares

| Share path | Purpose | Clients |
|-----------|---------|---------|
| `/mnt/core/k8s-volumes` | Kubernetes persistent volume claims | `10.0.10.0/24` |
| `/mnt/archive/k8s-backups` | etcd snapshots (mounted on tywin) + Docker appdata backups | `10.0.10.11`, `10.0.10.20` |
| `/mnt/archive/k8s-backups/rpi` | Raspberry Pi key material backups | `10.0.10.80` |

---

## Configuring NFS Shares in TrueNAS

Navigate to: **Shares → Unix (NFS) Shares → Add**

### Share: k8s-volumes

| Setting | Value |
|---------|-------|
| Path | `/mnt/core/k8s-volumes` |
| Description | Kubernetes persistent volumes |
| Maproot User | `root` |
| Maproot Group | `wheel` |
| Allowed Networks | `10.0.10.0/24` |
| Enable NFSv4 | Yes |
| Disable NFSv3 | Yes (if possible — better locking semantics) |

### Share: k8s-backups

| Setting | Value |
|---------|-------|
| Path | `/mnt/archive/k8s-backups` |
| Description | Kubernetes backup staging + Docker appdata backups |
| Maproot User | `root` |
| Maproot Group | `wheel` |
| Allowed Networks | `10.0.10.11/32`, `10.0.10.20/32` |
| Enable NFSv4 | Yes |

### Share: k8s-backups/rpi

| Setting | Value |
|---------|-------|
| Path | `/mnt/archive/k8s-backups/rpi` |
| Description | Raspberry Pi key material backups (GPG-encrypted) |
| Maproot User | `root` |
| Maproot Group | `wheel` |
| Allowed Networks | `10.0.10.10/32` |
| Enable NFSv4 | Yes |

> Create the subdirectory first on TrueNAS:
> ```bash
> zfs create archive/k8s-backups/rpi
> ```

---

## NFS Service Settings

Navigate to: **Services → NFS → Edit**

| Setting | Value |
|---------|-------|
| Number of threads | 8 (or match CPU core count) |
| Bind IP addresses | `10.0.10.80` (TrueNAS LAN IP only) |
| NFSv4 | Enabled |
| NFSv4 DNS Domain | *(leave blank or set your domain)* |

---

## Verifying NFS from Cluster Nodes

Run on any k3s node to verify the shares are exported:

```bash
showmount -e 10.0.10.80
```

Expected output:

```
Export list for 10.0.10.80:
/mnt/archive/k8s-backups/rpi  10.0.10.10
/mnt/archive/k8s-backups      10.0.10.11 10.0.10.20
/mnt/core/k8s-volumes      10.0.10.0/24
```

Test mounting manually:

```bash
sudo mount -t nfs 10.0.10.80:/mnt/core/k8s-volumes /tmp/test-nfs
ls /tmp/test-nfs
sudo umount /tmp/test-nfs
```

---

## NFS Mount on Control Plane (etcd backups)

The control plane node (tywin) mounts the backup share permanently for etcd snapshots.

`/etc/fstab` entry on tywin:

```
10.0.10.80:/mnt/archive/k8s-backups /mnt/backups nfs defaults,_netdev 0 0
```

See [Guide 08 — Cluster Backups](../../docs/guides/08-Cluster-Backups.md) for the full backup setup including the etcd snapshot cron job.

---

## Troubleshooting

**NFS mount hangs / times out**
- Verify the NFS service is enabled in TrueNAS: **Services → NFS** should show Active
- Check firewall: ports 111 (portmapper) and 2049 (NFS) must be open from `10.0.10.0/24`
- Verify the share allows the client IP/network

**Permission denied on mounted volume**
- Check Maproot User is set to `root` — k3s runs the NFS provisioner as root
- Verify the dataset permissions: `ls -la /mnt/core/k8s-volumes` in TrueNAS shell

**Stale NFS handle**
- The PVC backing directory was deleted on TrueNAS while still mounted in the cluster
- Delete and recreate the PVC, or remount the NFS share on the affected node
