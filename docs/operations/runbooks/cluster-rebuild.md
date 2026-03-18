
# Runbook — Full Cluster Rebuild

**Scenario:** The entire cluster must be rebuilt from scratch. All nodes are assumed to be at a bare OS or freshly imaged state.

**Target RTO:** 90–120 minutes from node availability to all workloads running.

> **Note on RTO:** The 90–120 min figure assumes no complications (network issues, TrueNAS unavailability, Flux CRD ordering delays). A worker-only rebuild is ~30 min. Control-plane + workers without etcd restore is ~60–90 min.

**Prerequisites:**
- Automation host with Ansible, kubectl, flux CLI, sops, age tools installed
- Access to the Git repository
- TrueNAS accessible at 10.0.10.80
- age private key (from offline backup)
- Most recent etcd snapshot at `/mnt/archive/backups/k8s/etcd/`

---

## Phase 1 — Node Preparation (~15 min)

Run all security and baseline playbooks against the newly imaged nodes.

```bash
cd ansible

# Baseline preparation
ansible-playbook ansible/playbooks/maintenance/upgrade-nodes.yml
ansible-playbook ansible/playbooks/security/disable-swap.yml
ansible-playbook ansible/playbooks/security/time-sync.yml
ansible-playbook ansible/playbooks/security/firewall.yml
ansible-playbook ansible/playbooks/security/ssh-hardening.yml
ansible-playbook ansible/playbooks/security/fail2ban.yml
```

Verify:

```bash
ansible all -m ping
```

All nodes must respond before proceeding.

---

## Phase 2 — Kubernetes Installation (~10 min)

```bash
ansible-playbook ansible/playbooks/lifecycle/install-cluster.yml
```

Verify:

```bash
kubectl get nodes
```

Expected:

```
tywin    Ready    control-plane
jaime    Ready    <none>
tyrion   Ready    <none>
```

```bash
kubectl get pods -A
```

All system pods should be Running before proceeding.

---

## Phase 3 — Restore etcd Snapshot (if recovering data) (~10 min)

If recovering from a failure where the etcd database was lost, restore the snapshot **before** bootstrapping Flux.

Mount the NFS share on tywin:

```bash
sudo mount 10.0.10.80:/mnt/archive/backups/k8s /mnt/backups
```

Identify the most recent snapshot:

```bash
ls -lht /mnt/backups/etcd/ | head -5
```

Restore:

```bash
# Stop k3s
sudo systemctl stop k3s

# Reset and restore from snapshot
sudo k3s server \
  --cluster-reset \
  --cluster-reset-restore-path=/mnt/backups/etcd/k3s-snapshot-YYYY-MM-DD_HHMMSS.db

# Start k3s
sudo systemctl start k3s
```

Wait for the control-plane to become ready:

```bash
kubectl wait --for=condition=Ready node/tywin --timeout=180s
```

Restart worker nodes to reconnect them:

```bash
ansible-playbook ansible/playbooks/maintenance/reboot-nodes.yml --limit jaime,tyrion
```

Verify all nodes Ready:

```bash
kubectl get nodes
```

---

## Phase 4 — Restore the age Private Key (~2 min)

The SOPS age private key must be in the cluster before Flux can decrypt secrets.

```bash
# Retrieve age.key from offline backup storage
# Then:
kubectl create namespace flux-system || true
kubectl create secret generic sops-age \
  --namespace=flux-system \
  --from-file=age.agekey=/path/to/age.key
```

---

## Phase 5 — Bootstrap Flux (~15 min)

```bash
flux bootstrap git \
  --url=ssh://git@github.com/<USER>/homelab-infrastructure.git \
  --branch=main \
  --path=clusters/prod \
  --private-key-file=$HOME/.ssh/flux_deploy_key
```

Monitor reconciliation:

```bash
flux get kustomizations --watch
```

Expected reconciliation order (see `infrastructure.yaml` dependsOn chain):

1. `flux-system` — Flux controllers
2. `platform-networking` — MetalLB, Traefik
3. `platform-security` — cert-manager, ClusterIssuers
4. `platform-namespaces` — namespace creation
5. `platform-observability` — kube-prometheus-stack, Loki
6. `platform-storage` — NFS provisioner
7. `platform-backup` — Velero
8. `platform-upgrade` — system-upgrade-controller
9. `apps` — application workloads

Wait for all Kustomizations to show `Ready`. This step takes the longest due to Helm chart pulls and CRD registration.

---

## Phase 6 — Restore Persistent Volume Data with Velero (~15 min)

Once Velero is running (reconciled by Flux), restore the most recent backup:

```bash
# List available backups
velero backup get

# Restore the most recent full backup
velero restore create --from-backup <backup-name> --wait
```

Monitor restore progress:

```bash
velero restore get
velero restore describe <restore-name>
```

If the backup is stored on Backblaze B2 (most recent TrueNAS sync was before MinIO failure), the TrueNAS MinIO instance must be restored first from B2 before Velero can access it.

---

## Phase 7 — Verification (~10 min)

```bash
# All nodes ready
kubectl get nodes

# All pods running
kubectl get pods -A | grep -Ev 'Running|Completed'

# Flux reconciliation healthy
flux get all -A

# Backup metrics restored
ls /mnt/backups/etcd/

# Ingress responding
curl -sI https://grafana.kagiso.me | head -5
```

Confirm in Grafana:
- All dashboards loading
- No active alerts
- Node metrics present for all three nodes

---

## Expected Timeline

| Phase | Duration | Notes |
|-------|----------|-------|
| Node preparation | ~15 min | Ansible baseline playbooks |
| k3s installation | ~10 min | install-cluster.yml |
| etcd restore (if needed) | ~10 min | Skip if clean rebuild |
| age key restore | ~2 min | |
| Flux bootstrap + reconciliation | ~15–30 min | HelmRelease pulls vary by registry speed |
| Velero PV restore | ~15 min | Depends on data volume |
| Verification | ~10 min | |
| **Total** | **~90–120 min** | Worker-only: ~30 min; CP only: ~60–90 min |

---

## Post-Rebuild Checklist

```
□ All nodes show Ready
□ All Flux Kustomizations Ready
□ All HelmReleases Ready
□ Grafana accessible at https://grafana.kagiso.me
□ Traefik dashboard accessible
□ Alertmanager receivers responding (send test alert)
□ Backup cron job running (crontab -l on tywin)
□ NFS mount in /etc/fstab on tywin
□ Test backup: k3s etcd-snapshot save manual-post-rebuild
□ Confirm snapshot appears in /mnt/archive/backups/k8s/etcd/
□ Velero backup status: velero backup get
□ TLS certificates issued: kubectl get certificates -A
```
