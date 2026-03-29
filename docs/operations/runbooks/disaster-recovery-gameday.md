# Runbook - Disaster Recovery Game Day

**Scenario:** Rehearsing backup and restore procedures before a real incident forces them.

> A runbook is only trustworthy when it has been exercised recently enough to catch drift.

---

## Objectives

This game day proves four things:

1. backup artefacts exist where the docs say they exist
2. restore commands still match the current platform topology
3. operators can recover within the documented RTO
4. gaps found during rehearsal are turned into tracked follow-up work

---

## Cadence

| Frequency | Scope | Target |
|---|---|---|
| Monthly | Docker appdata non-destructive restore drill | Validate latest archive and restore script behaviour |
| Quarterly | Kubernetes cluster restore rehearsal | Validate etcd, Flux, and Velero recovery flow |
| After backup-path changes | Targeted retest | Validate the specific path that changed before calling it done |

---

## Part A - Monthly Docker Drill Restore

Run on the Docker host (`10.0.10.20`).

### Step 1 - Identify the latest archive

```bash
ls -lht /mnt/archive/backups/docker/ | head -5
```

### Step 2 - Run the restore in drill mode

```bash
sudo bash /srv/docker/scripts/restore_docker.sh \
  --target-root /srv/docker/restore-drill/<date> \
  /mnt/archive/backups/docker/docker_appdata_YYYY-MM-DD_HHMMSS.tar.gz
```

Expected behaviour:

- running containers stay up
- archive extracts under `/srv/docker/restore-drill/<date>/srv/docker/appdata`
- the script prints validation suggestions instead of production restart steps

### Step 3 - Validate the extracted contents

```bash
find /srv/docker/restore-drill/<date>/srv/docker/appdata -maxdepth 2 -type d | sort | head -40
```

Confirm that the expected application directories exist, for example:

- `plex`
- `sonarr`
- `radarr`
- `prowlarr`
- `sabnzbd`
- `npm`

### Step 4 - Clean up the drill directory

```bash
sudo rm -rf /srv/docker/restore-drill/<date>
```

### Evidence to record

- date
- operator
- archive tested
- restore duration
- directories verified
- defects found

---

## Part B - Quarterly Kubernetes Restore Rehearsal

Run this in a disposable environment or on spare hardware. Do not test destructive cluster restore steps on the live cluster unless the goal is a real recovery.

### Step 1 - Prepare the rehearsal target

- provision the target nodes or VM set
- ensure network reachability to TrueNAS and GitHub
- mount the backup share

### Step 2 - Rebuild the cluster baseline

```bash
ansible-playbook -i ansible/inventory/homelab.yml ansible/playbooks/lifecycle/install-cluster.yml
```

### Step 3 - Restore etcd

Follow [Backup Restoration](./backup-restoration.md) for the exact sequence.

Minimum success criteria:

- kube-vip endpoint reachable at `10.0.10.100`
- `kubectl get nodes` shows all restored server nodes `Ready`
- Flux bootstrap can proceed cleanly

### Step 4 - Restore platform state from Git

```bash
ansible-playbook -i ansible/inventory/homelab.yml ansible/playbooks/lifecycle/install-platform.yml
```

### Step 5 - Restore PVC-backed data with Velero

```bash
velero backup get
velero restore create --from-backup <backup-name>
velero restore get
```

### Step 6 - Validate critical paths

At minimum, verify:

- Flux kustomizations reconcile successfully
- Traefik is reachable on `10.0.10.110`
- one critical application path works end to end
- monitoring data and dashboards are present where expected

### Evidence to record

- snapshot used
- Velero backup used
- total rehearsal duration
- failures encountered
- manual steps that were missing from the docs
- follow-up actions raised

---

## Pass / Fail Criteria

The game day passes when:

- the documented steps work without hidden tribal knowledge
- actual restore time is within the documented target or the target is updated honestly
- any discovered drift is fixed in Git immediately after the rehearsal

The game day fails when:

- a required artefact is missing
- the restore depends on undocumented manual state
- the restore completes only by improvising around stale docs or broken scripts

---

## After Action

Every rehearsal should end with one of two outcomes:

- no issues found, with evidence recorded
- issues found, with docs and code updated before the next cycle

Do not let game-day findings live only in memory or chat.
