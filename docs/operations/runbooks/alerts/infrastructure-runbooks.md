# Infrastructure Alert Runbooks

| Field | Value |
|-------|-------|
| File | infrastructure-runbooks.md |
| Covers | DockerHostDown, DockerContainerDown, DockerContainerRestarting, DockerHostDiskFull, DockerHostMemoryHigh, DockerNFSMountMissing, RpiDown, RpiSDCardFull, RpiSDCardCritical, TrueNASDown, TrueNASDiskFull, TrueNASDiskCritical |
| Last Updated | 2026-03-15 |

**Quick Reference â€” Host Access:**
- RPi Control Hub: `ssh kagiso@10.0.10.10`
- Docker Media Server: `ssh kagiso@10.0.10.20`
- TrueNAS: `ssh admin@10.0.10.80` or UI at http://10.0.10.80
- k3s Control Plane (tywin): `ssh kagiso@10.0.10.11`
- NFS mounts on Docker host: `/mnt/media`, `/mnt/downloads`, `/mnt/archive`

---

## Table of Contents

1. [DockerHostDown](#dockerhostdown)
2. [DockerContainerDown](#dockercontainerdown)
3. [DockerContainerRestarting](#dockercontainerrestarting)
4. [DockerHostDiskFull](#dockerhostdiskfull)
5. [DockerHostMemoryHigh](#dockerhostmemoryhigh)
6. [DockerNFSMountMissing](#dockernfsmountmissing)
7. [RpiDown](#rpidown)
8. [RpiSDCardFull](#rpisdcardfull)
9. [RpiSDCardCritical](#rpisdcardcritical)
10. [TrueNASDown](#truenasdown)
11. [TrueNASDiskFull](#truenasdiskfull)
12. [TrueNASDiskCritical](#truenasdiskcritical)

---

## DockerHostDown

| Field | Value |
|-------|-------|
| Severity | Critical |
| Threshold | Host `10.0.10.20` unreachable for > 2 minutes (Prometheus up == 0) |
| First Response | 10 minutes |

### What This Alert Means

The Docker media server at `10.0.10.20` is not responding to Prometheus scrapes. The host may be powered off, crashed, or has lost network connectivity. All media services (Plex, *arr stack, etc.) are down.

### Diagnostic Steps

1. First, verify from the RPi that the host is truly unreachable:
   ```bash
   ssh kagiso@10.0.10.10
   ping -c 4 10.0.10.20
   ```

2. Attempt SSH:
   ```bash
   ssh -o ConnectTimeout=10 kagiso@10.0.10.20
   ```

3. Check if the host is visible on the network (ARP):
   ```bash
   arp -n | grep 10.0.10.20
   # No entry = host is not broadcasting (powered off or network issue)
   ```

4. If you have physical access or IPMI/wake-on-LAN:
   ```bash
   # Send Wake-on-LAN magic packet (from RPi if WoL is configured):
   wakeonlan <mac-address-of-docker-host>
   # Or check your router/switch admin panel for the host's MAC
   ```

5. Check if other hosts on the same subnet are reachable:
   ```bash
   ping -c 2 10.0.10.80  # TrueNAS
   ping -c 2 10.0.10.11  # tywin
   ```

6. If only the Docker host is unreachable and others are fine, the host has crashed or lost power.

7. Once the host is back online, verify Docker is running:
   ```bash
   ssh kagiso@10.0.10.20
   systemctl status docker
   docker ps
   ```

8. Check system logs for crash cause:
   ```bash
   ssh kagiso@10.0.10.20
   journalctl -b -1 | tail -50  # logs from previous boot
   dmesg | tail -30
   ```

### Decision Table

| Condition | Action |
|-----------|--------|
| Host unreachable, others fine | Physical power issue; check power/PSU |
| Whole subnet unreachable | Network switch/router issue; check 10.0.10.x gateway |
| Host responds to ping, SSH fails | SSH service or sshd crashed; physical console required |
| Docker daemon not running after boot | `systemctl start docker && systemctl enable docker` |
| NFS mounts missing after reboot | See [DockerNFSMountMissing](#dockernfsmountmissing) |

### Verify Recovery

```bash
ssh kagiso@10.0.10.10
ping -c 2 10.0.10.20
ssh kagiso@10.0.10.20 "docker ps && df -h /mnt/media"
# All containers running, NFS mounts present
```

---

## DockerContainerDown

| Field | Value |
|-------|-------|
| Severity | Warning |
| Threshold | Specific Docker container not running for > 5 minutes |
| First Response | 20 minutes |

### What This Alert Means

A Docker container on the media server (10.0.10.20) has exited and is not being restarted automatically. The container may have crashed, been stopped manually, or its restart policy may be `no` or `on-failure` with exceeded retries.

### Diagnostic Steps

1. SSH to bronn and identify the stopped container:
   ```bash
   ssh kagiso@10.0.10.20
   docker ps -a --format "table {{.Names}}\t{{.Status}}\t{{.Image}}" | grep -v "Up"
   ```

2. Check why the container stopped:
   ```bash
   docker inspect <container-name> --format='{{.State.Status}} {{.State.ExitCode}} {{.State.Error}}'
   docker logs <container-name> --tail=100
   ```

3. Check exit code:
   ```bash
   docker inspect <container-name> --format='ExitCode: {{.State.ExitCode}}'
   ```

   | Exit Code | Meaning |
   |-----------|---------|
   | 0 | Clean exit (intentional stop) |
   | 1 | Application error |
   | 137 | OOM killed |
   | 139 | Segfault |
   | 143 | SIGTERM (graceful shutdown) |

4. Check the container's restart policy:
   ```bash
   docker inspect <container-name> --format='{{.HostConfig.RestartPolicy}}'
   ```

5. Check available disk and memory (resource exhaustion can stop containers):
   ```bash
   df -h
   free -h
   ```

6. Attempt to restart the container:
   ```bash
   docker start <container-name>
   docker logs <container-name> -f --tail=30  # watch for immediate crash
   ```

7. If the container crashes immediately on restart, check NFS mounts (media apps depend on them):
   ```bash
   mount | grep nfs
   ls /mnt/media /mnt/downloads /mnt/archive
   ```

### Decision Table

| Condition | Action |
|-----------|--------|
| Exit code 0, restart policy `no` | Was stopped manually; restart if appropriate |
| Exit code 137 | OOM; increase Docker memory limit or reduce workload |
| NFS mount missing | See [DockerNFSMountMissing](#dockernfsmountmissing) |
| Application config error | Review app logs; fix config in compose file |
| Container starts then crashes | Review full logs; may be dependency issue |

### Verify Recovery

```bash
ssh kagiso@10.0.10.20
docker ps | grep <container-name>
# Container should show "Up X minutes"
```

---

## DockerContainerRestarting

| Field | Value |
|-------|-------|
| Severity | Warning |
| Threshold | Container restart count increases > 3 times in 1 hour |
| First Response | 30 minutes |

### What This Alert Means

A Docker container on the media server is in a restart loop. Unlike Kubernetes CrashLoopBackOff, Docker will keep restarting containers indefinitely with its `unless-stopped` or `always` restart policy. The container is failing repeatedly.

### Diagnostic Steps

1. Check restart count and current state:
   ```bash
   ssh kagiso@10.0.10.20
   docker inspect <container-name> --format='Restarts: {{.RestartCount}} Status: {{.State.Status}}'
   ```

2. Look at the logs from the most recent failure:
   ```bash
   docker logs <container-name> --tail=200 --timestamps 2>&1 | tail -100
   ```

3. Check what the container is trying to do and failing at:
   ```bash
   docker inspect <container-name> --format='{{json .State}}' | python3 -m json.tool
   ```

4. Check system resources:
   ```bash
   free -h
   df -h
   docker stats --no-stream
   ```

5. Check if the container depends on NFS mounts that may have dropped:
   ```bash
   mount | grep nfs
   docker inspect <container-name> --format='{{json .Mounts}}' | python3 -m json.tool
   ```

6. Check if there's a port conflict:
   ```bash
   docker inspect <container-name> --format='{{json .HostConfig.PortBindings}}' | python3 -m json.tool
   ss -tlnp | grep <port>
   ```

### Decision Table

| Condition | Action |
|-----------|--------|
| Logs show "permission denied" | Fix volume mount ownership: `chown -R <uid>:<gid> /path/to/volume` |
| Logs show OOM kill | Increase `mem_limit` in docker-compose.yml |
| Port in use by another process | Kill conflicting process or change container port |
| NFS mount missing | See [DockerNFSMountMissing](#dockernfsmountmissing) |
| Application error | Check app-specific documentation |

### Verify Recovery

```bash
ssh kagiso@10.0.10.20
docker stats --no-stream <container-name>
docker inspect <container-name> --format='Restarts: {{.RestartCount}}'
# Restart count should stop increasing
```

---

## DockerHostDiskFull

| Field | Value |
|-------|-------|
| Severity | Critical |
| Threshold | Disk usage on local filesystem of 10.0.10.20 > 90% |
| First Response | 15 minutes |

### What This Alert Means

The local disk on the Docker media server (`10.0.10.20`) is over 90% full. Note: `/mnt/media`, `/mnt/downloads`, and `/mnt/archive` are NFS mounts and have their own alerts. This alert refers to the root or Docker data partition.

### Diagnostic Steps

1. SSH to Docker host and check all filesystems:
   ```bash
   ssh kagiso@10.0.10.20
   df -h
   # Identify which partition is full (usually / or /var)
   ```

2. Find what's consuming space:
   ```bash
   du -sh /* 2>/dev/null | sort -rh | head -15
   du -sh /var/* 2>/dev/null | sort -rh | head -10
   ```

3. Check Docker-specific space usage:
   ```bash
   docker system df -v
   ```

4. Clean up Docker artifacts:
   ```bash
   # Remove stopped containers:
   docker container prune -f

   # Remove unused images:
   docker image prune -a -f

   # Remove unused volumes (CAREFUL â€” verify before running):
   docker volume ls -qf dangling=true
   # docker volume prune -f  # only after confirming volumes are unused

   # Remove build cache:
   docker builder prune -f
   ```

5. Check for large log files:
   ```bash
   find /var/log -type f -size +100M 2>/dev/null
   journalctl --disk-usage
   ```

6. Truncate old journal logs if large:
   ```bash
   sudo journalctl --vacuum-size=500M
   sudo journalctl --vacuum-time=7d
   ```

7. Check Docker container log file sizes:
   ```bash
   du -sh /var/lib/docker/containers/*/  | sort -rh | head -10
   ```

8. Check if any container has logging without size limits:
   ```bash
   docker inspect $(docker ps -q) --format='{{.Name}} {{json .HostConfig.LogConfig}}' | grep -v "max-size"
   ```

### Decision Table

| Condition | Action |
|-----------|--------|
| Docker images taking most space | `docker image prune -a -f` |
| Container logs unbounded | Add `--log-opt max-size=100m --log-opt max-file=3` to container |
| /var/log full | Truncate old logs; enable log rotation |
| Old downloads in wrong location | Move to /mnt/downloads (NFS) if that was the intent |

### Verify Recovery

```bash
ssh kagiso@10.0.10.20
df -h /
# Should be below 85%
docker system df
```

---

## DockerHostMemoryHigh

| Field | Value |
|-------|-------|
| Severity | Warning |
| Threshold | Memory usage > 85% for > 15 minutes |
| First Response | 30 minutes |

### What This Alert Means

The Docker media server's RAM is consistently over 85% utilized. This risks triggering the OOM killer, which will kill processes (possibly important containers) arbitrarily to reclaim memory. Media transcoding (Plex/Jellyfin) is a common cause.

### Diagnostic Steps

1. Check overall memory usage:
   ```bash
   ssh kagiso@10.0.10.20
   free -h
   cat /proc/meminfo | grep -E "MemTotal|MemFree|MemAvailable|Cached|Buffers"
   ```

2. Find which containers are using the most memory:
   ```bash
   docker stats --no-stream --format "table {{.Name}}\t{{.MemUsage}}\t{{.MemPerc}}" | sort -k3 -rn | head -10
   ```

3. Check system processes outside of Docker:
   ```bash
   ps aux --sort=-%mem | head -15
   ```

4. Check if Plex/Jellyfin is transcoding:
   ```bash
   docker logs plex --tail=30 | grep -i transcode
   docker logs jellyfin --tail=30 | grep -i transcode
   ls -lah /tmp/jellyfin-transcodes/ 2>/dev/null
   ```

5. Check if swap is configured and being used:
   ```bash
   swapon --show
   vmstat 1 5
   ```

6. Check for memory leaks in long-running containers:
   ```bash
   # Check if a container's memory is growing over time:
   docker stats --format "{{.Name}}: {{.MemUsage}}" | sort -k2 -rn
   ```

### Decision Table

| Condition | Action |
|-----------|--------|
| Plex transcoding at high quality | Force lower quality or enable hardware transcoding |
| Container with no memory limit | Add `mem_limit:` to docker-compose.yml |
| Single container consuming >50% | Restart that container; investigate memory leak |
| No swap configured | Add swap: `sudo fallocate -l 4G /swapfile && sudo mkswap /swapfile && sudo swapon /swapfile` |
| Legitimate high usage | Consider adding RAM or offloading workloads |

### Verify Recovery

```bash
ssh kagiso@10.0.10.20
free -h
docker stats --no-stream | sort -k4 -rn | head -5
# Available memory should be >15%
```

---

## DockerNFSMountMissing

| Field | Value |
|-------|-------|
| Severity | Critical |
| Threshold | NFS mount (`/mnt/media`, `/mnt/downloads`, or `/mnt/archive`) not mounted |
| First Response | 10 minutes |

### What This Alert Means

One or more NFS mounts from TrueNAS (10.0.10.80) are missing on the Docker host (10.0.10.20). All media containers that depend on these mounts will fail to read/write files. This typically causes immediate container failures or silent data issues.

### Diagnostic Steps

1. SSH to Docker host and check current mounts:
   ```bash
   ssh kagiso@10.0.10.20
   mount | grep nfs
   ls -la /mnt/media /mnt/downloads /mnt/archive
   ```

2. Check if TrueNAS is reachable:
   ```bash
   ping -c 4 10.0.10.80
   showmount -e 10.0.10.80
   ```

3. Check what's in /etc/fstab for NFS entries:
   ```bash
   grep nfs /etc/fstab
   ```

4. Attempt to remount:
   ```bash
   sudo mount -a
   # Check for errors:
   mount | grep nfs
   ```

5. If `mount -a` fails, try mounting individually:
   ```bash
   sudo mount -t nfs 10.0.10.80:/mnt/tera /mnt/media
   sudo mount -t nfs 10.0.10.80:/mnt/tera /mnt/downloads
   sudo mount -t nfs 10.0.10.80:/mnt/archive /mnt/archive
   ```

6. Check NFS server exports on TrueNAS if mount fails:
   ```bash
   ssh admin@10.0.10.80 "showmount -e localhost"
   # Or via TrueNAS UI: Services â†’ NFS â†’ verify NFS service is running
   ```

7. Check dmesg for NFS errors:
   ```bash
   ssh kagiso@10.0.10.20
   dmesg | grep -i "nfs\|mount" | tail -20
   ```

8. After remounting, restart affected containers:
   ```bash
   docker restart plex jellyfin sonarr radarr  # adjust to your actual container names
   ```

### Decision Table

| Condition | Action |
|-----------|--------|
| TrueNAS unreachable | See [TrueNASDown](#truenasdown) |
| TrueNAS up, NFS not exporting | Restart NFS service in TrueNAS UI; check shares config |
| Mount fails with "access denied" | Check NFS export permissions on TrueNAS for 10.0.10.20 |
| Mount succeeds but containers broken | Restart affected containers |
| Stale NFS handle errors | `sudo umount -l /mnt/media && sudo mount /mnt/media` |

### Verify Recovery

```bash
ssh kagiso@10.0.10.20
mount | grep nfs
ls /mnt/media/ | head -5  # Should show media files
docker ps | grep -v "Up"  # All containers should be running
```

---

## RpiDown

| Field | Value |
|-------|-------|
| Severity | Critical |
| Threshold | RPi at `10.0.10.10` unreachable for > 5 minutes |
| First Response | 10 minutes |

### What This Alert Means

The hodor control hub at `10.0.10.10` is not responding. This host runs kubectl, flux CLI, and serves as the primary operational interface to the cluster. Loss of this host means loss of cluster management access (unless you have an alternative kubectl config).

### Diagnostic Steps

1. Check if the RPi is reachable from another host:
   ```bash
   # From your workstation:
   ping -c 4 10.0.10.10
   ssh -o ConnectTimeout=10 kagiso@10.0.10.10
   ```

2. Check if other hosts on the same subnet are up:
   ```bash
   ping -c 2 10.0.10.11  # tywin
   ping -c 2 10.0.10.20  # docker host
   ```

3. If only RPi is unreachable:
   - Check physical power LED on the RPi
   - Check if SD card is still seated
   - Check if the RPi is overheating (RPis throttle and sometimes lock up)

4. If you have physical access, connect a monitor/keyboard to the RPi.

5. Try Wake-on-LAN if configured, or power cycle the RPi.

6. If the RPi is truly down, establish alternative kubectl access from your workstation:
   ```bash
   # Copy kubeconfig from tywin (if you have access):
   ssh kagiso@10.0.10.11 "sudo cat /etc/rancher/k3s/k3s.yaml" | \
     sed 's/127.0.0.1/10.0.10.11/' > ~/.kube/config-homelab
   export KUBECONFIG=~/.kube/config-homelab
   kubectl get nodes
   ```

7. Once RPi is back up, check SD card health:
   ```bash
   ssh kagiso@10.0.10.10
   dmesg | grep -i "mmc\|mmcblk\|error" | tail -20
   df -h /
   ```

### Decision Table

| Condition | Action |
|-----------|--------|
| RPi crashed, SD card healthy | Power cycle; will auto-recover |
| SD card IO errors in dmesg | See [RpiSDCardCritical](#rpisdcardcritical) |
| SD card full | See [RpiSDCardFull](#rpisdcardfull) |
| Network issue only | Check switch port; check static IP assignment |
| RPi won't boot | Physical repair/replacement required |

### Verify Recovery

```bash
ping -c 2 10.0.10.10
ssh kagiso@10.0.10.10 "kubectl get nodes"
# All k3s nodes should show Ready
```

---

## RpiSDCardFull

| Field | Value |
|-------|-------|
| Severity | Warning |
| Threshold | RPi root filesystem usage > 80% |
| First Response | 2 hours |

### What This Alert Means

The SD card on the RPi control hub (10.0.10.10) is more than 80% full. SD cards on RPi devices that fill up cause write failures that can corrupt the OS or prevent logging. Proactive cleanup is needed.

### Diagnostic Steps

1. SSH to the RPi and check disk usage:
   ```bash
   ssh kagiso@10.0.10.10
   df -h /
   ```

2. Find what's consuming space:
   ```bash
   sudo du -sh /* 2>/dev/null | sort -rh | head -15
   sudo du -sh /home/* /var/* /tmp 2>/dev/null | sort -rh | head -10
   ```

3. Clean up package caches:
   ```bash
   sudo apt-get clean
   sudo apt-get autoremove -y
   ```

4. Check and truncate journal logs:
   ```bash
   journalctl --disk-usage
   sudo journalctl --vacuum-size=200M
   sudo journalctl --vacuum-time=14d
   ```

5. Check for large files in home directory:
   ```bash
   find /home/kagiso -type f -size +50M 2>/dev/null
   ```

6. Check kubectl/helm artifact caches:
   ```bash
   du -sh ~/.kube/ ~/.config/ ~/.cache/ ~/.local/ 2>/dev/null | sort -rh
   ```

7. Remove old Flux CLI versions or unused binaries:
   ```bash
   ls -lah /usr/local/bin/
   ```

8. Check if the homelab Git repo clone is large:
   ```bash
   du -sh ~/homelab-infrastructure/
   git -C ~/homelab-infrastructure gc --prune=now
   ```

### Verify Recovery

```bash
ssh kagiso@10.0.10.10
df -h /
# Should be below 75%
```

---

## RpiSDCardCritical

| Field | Value |
|-------|-------|
| Severity | Critical |
| Threshold | RPi root filesystem usage > 95%, or IO errors in dmesg |
| First Response | 15 minutes |

### What This Alert Means

The RPi SD card is critically full (>95%) or is showing IO errors indicating the SD card is failing. A full SD card will cause the OS to become read-only and crash; a failing SD card risks data loss including SOPS age keys.

### Diagnostic Steps

1. Check disk and IO error status immediately:
   ```bash
   ssh kagiso@10.0.10.10
   df -h /
   dmesg | grep -i "mmc\|mmcblk\|I/O error\|error" | tail -30
   ```

2. If IO errors are present, immediately back up critical data:
   ```bash
   # Backup SOPS age key to TrueNAS:
   scp ~/.config/sops/age/keys.txt admin@10.0.10.80:/mnt/archive/rpi/age-keys-emergency.txt

   # Backup kubeconfig:
   scp ~/.kube/config admin@10.0.10.80:/mnt/archive/rpi/kubeconfig-emergency

   # Backup any local scripts:
   tar czf - ~/homelab-infrastructure/ | ssh admin@10.0.10.80 "cat > /mnt/archive/rpi/repo-emergency.tar.gz"
   ```

3. If only disk full (no IO errors), aggressively free space:
   ```bash
   sudo apt-get clean && sudo apt-get autoremove -y
   sudo journalctl --vacuum-size=100M
   sudo rm -rf /tmp/* /var/tmp/*
   # Remove any large cached files:
   find /home /var /tmp -type f -size +10M -not -path "/var/lib/*" 2>/dev/null | xargs ls -lah | sort -k5 -rh | head -20
   ```

4. If SD card is failing (IO errors), plan immediate replacement:
   - Boot from USB if possible: `sudo raspi-config` â†’ Boot Options â†’ USB Boot
   - Clone SD card if still readable: use another Pi or SD card reader with `dd`

5. As a workaround, remount root as read-only to prevent further corruption (if still writable):
   ```bash
   # This is a last resort â€” the Pi will be unusable for writes
   sudo mount -o remount,ro /
   ```

### Decision Table

| Condition | Action |
|-----------|--------|
| Disk full, no IO errors | Free space immediately (step 3) |
| IO errors present | Backup now; prepare SD card replacement |
| SD card unreadable | Physical recovery; restore from [backup-restoration.md](../backup-restoration.md) |
| Alternative kubectl access needed | See [RpiDown](#rpidown) step 6 |

### Verify Recovery

```bash
ssh kagiso@10.0.10.10
df -h /
dmesg | grep -i "mmc\|mmcblk" | tail -10
# No IO errors, disk usage below 85%
```

---

## TrueNASDown

| Field | Value |
|-------|-------|
| Severity | Critical |
| Threshold | TrueNAS at `10.0.10.80` unreachable for > 3 minutes |
| First Response | 10 minutes |

### What This Alert Means

TrueNAS SCALE at `10.0.10.80` is not responding to Prometheus scrapes. This is the primary NAS providing NFS storage to the Docker host, k3s cluster (if using NFS PVCs), and backup storage. Downstream effects: Docker NFS mounts will stall/fail, Velero backups will fail, media services will go offline.

### Diagnostic Steps

1. Verify TrueNAS is truly unreachable:
   ```bash
   ssh kagiso@10.0.10.10
   ping -c 4 10.0.10.80
   curl -s --connect-timeout 5 http://10.0.10.80 | head -5
   ```

2. Check if the ZFS pools (core/archive/tera) was in a degraded state before the outage (check recent alerts).

3. Try SSH to TrueNAS:
   ```bash
   ssh -o ConnectTimeout=10 admin@10.0.10.80
   ```

4. Check the TrueNAS web UI: http://10.0.10.80

5. If TrueNAS is completely unreachable, check physical status:
   - Power LED on NAS enclosure
   - Any beep codes
   - Check network switch for the port connected to 10.0.10.80

6. Once reachable, verify ZFS pool is healthy:
   ```bash
   ssh admin@10.0.10.80
   zpool status
   zpool list
   ```

7. Check TrueNAS services that need to be running:
   ```bash
   ssh admin@10.0.10.80
   # Or via TrueNAS UI: Services â†’ check NFS, SMB status
   midclt call service.query | python3 -m json.tool | grep -A5 "nfs\|smb"
   ```

8. After TrueNAS recovers, force remount on Docker host:
   ```bash
   ssh kagiso@10.0.10.20
   sudo umount -l /mnt/media /mnt/downloads /mnt/archive 2>/dev/null
   sudo mount -a
   mount | grep nfs
   ```

### Decision Table

| Condition | Action |
|-----------|--------|
| TrueNAS crashed/rebooting | Wait for it to come back; check pool after |
| ZFS pool degraded/faulted | See [ZFSPoolDegraded](truenas-runbooks.md#zpoolpooldegraded) |
| NFS service not started | Start via TrueNAS UI: Services â†’ NFS â†’ toggle on |
| Network issue | Check switch port; check TrueNAS network configuration |
| TrueNAS won't boot | Physical intervention; check disk health |

### Verify Recovery

```bash
ssh kagiso@10.0.10.10
ping -c 2 10.0.10.80
ssh admin@10.0.10.80 "zpool status | grep state"
# state: ONLINE

# Verify Docker host can access NFS again:
ssh kagiso@10.0.10.20 "ls /mnt/media | head -3"
```

---

## TrueNASDiskFull

| Field | Value |
|-------|-------|
| Severity | Warning |
| Threshold | ZFS pools (core/archive/tera) usage > 80% |
| First Response | 2 hours |

### What This Alert Means

The ZFS pools (core/archive/tera) on TrueNAS (10.0.10.80) is over 80% full. ZFS performance degrades significantly above 80% and writes can fail at higher usage. This pool holds media files, backups, and NFS exports.

### Diagnostic Steps

1. Check pool usage:
   ```bash
   ssh admin@10.0.10.80
   zpool list
   zfs list | sort -k3 -rh | head -20
   ```

2. Find the largest datasets:
   ```bash
   zfs list -t filesystem,volume -o name,used,refer -o name,used,refer | sort -k2 -rh | head -15
   ```

3. Check snapshots (they can consume significant space):
   ```bash
   zfs list -t snapshot | sort -k2 -rh | head -20
   zfs list -t snapshot -o name,used | awk '{sum+=$2} END {print "Total snapshot space:", sum}'
   ```

4. Check backup directories specifically:
   ```bash
   zfs list archive/backups/k8s 2>/dev/null
   du -sh /mnt/archive/* 2>/dev/null | sort -rh | head -10
   ```

5. Check media dataset usage:
   ```bash
   du -sh /mnt/tera/* 2>/dev/null | sort -rh | head -10
   ```

6. Look for duplicate or unnecessary files in the downloads area:
   ```bash
   du -sh /mnt/tera/* 2>/dev/null | sort -rh | head -10
   ```

### Decision Table

| Condition | Action |
|-----------|--------|
| Excessive snapshots | Delete old snapshots: `zfs destroy archive/backups/k8s@<snapshot-name>` |
| Old backup archives | `find /mnt/archive -mtime +60 -name "*.tar.gz" -delete` |
| Downloads not cleaned up | Trigger *arr stack to remove completed downloads |
| Dataset genuinely large | Evaluate adding storage or moving data |

### Verify Recovery

```bash
ssh admin@10.0.10.80
zpool list
# ALLOC/FREE should show <80% usage
```

---

## TrueNASDiskCritical

| Field | Value |
|-------|-------|
| Severity | Critical |
| Threshold | ZFS pools (core/archive/tera) usage > 92% |
| First Response | 15 minutes |

### What This Alert Means

The ZFS pools (core/archive/tera) is over 92% full. At this level, ZFS may refuse writes, metadata operations can fail, and pool corruption risk increases significantly. Immediate space recovery is required.

### Diagnostic Steps

Follow all steps from [TrueNASDiskFull](#truenasdiskfull), then act immediately:

1. Identify and delete old snapshots urgently:
   ```bash
   ssh admin@10.0.10.80
   # List all snapshots with sizes, sorted by size:
   zfs list -t snapshot -o name,used,creation | sort -k2 -rh | head -30

   # Destroy old snapshots (DO NOT destroy the most recent ones):
   zfs destroy <pool>@<old-snapshot-name>
   # Or destroy a range:
   zfs destroy <pool>@<oldest>%<newest-to-delete>
   ```

2. Remove old backup archives immediately:
   ```bash
   # Backups older than 14 days:
   find /mnt/archive -type f -mtime +14 -name "*.tar.gz" | head -20
   # After reviewing:
   find /mnt/archive -type f -mtime +14 -name "*.tar.gz" -delete
   ```

3. Check and remove completed Velero backups from storage:
   ```bash
   # From RPi:
   ssh kagiso@10.0.10.10
   velero backup get | grep Completed | sort -k5
   velero backup delete <oldest-backup-name>
   ```

4. If pool is at >95%, consider emergency measures:
   ```bash
   ssh admin@10.0.10.80
   # Delete all but most recent snapshots for non-critical datasets:
   zfs list -t snapshot -r tera -o name -H | head -n -2 | xargs -n1 zfs destroy
   ```

5. Alert is critical: do not wait to clean up â€” pool writes may already be failing.

### Verify Recovery

```bash
ssh admin@10.0.10.80
zpool list
# ALLOC should be <85% of SIZE
zpool status | grep state
# state: ONLINE
```
