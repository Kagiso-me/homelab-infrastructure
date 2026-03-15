# TrueNAS — Monitoring Setup
## Exposing ZFS and SMART Metrics to Prometheus

---

## Why Monitor TrueNAS?

Hard drives fail silently. By the time a drive produces visible errors — data corruption, a failed scrub, a pool degrading — the window for a clean replacement has often already closed. The SMART (Self-Monitoring, Analysis and Reporting Technology) standard was designed precisely to address this: drives continuously measure their own internal health indicators and expose them as numbered attributes. In practice, certain SMART attributes reliably provide a **24–72 hour warning** before a complete drive failure.

ZFS compounds this advantage. Unlike traditional filesystems, ZFS tracks checksum errors, vdev state, and scrub results at the filesystem level and exposes them as kernel statistics. When node-exporter scrapes these, Prometheus can alert on a degraded vdev or rising checksum errors before a user ever notices a problem.

Running both exporters on TrueNAS gives you:

- **Disk health trending** — see Temperature_Celsius climbing over weeks, Reallocated_Sector_Ct ticking upward
- **Pool state monitoring** — instant alert if a pool goes from ONLINE to DEGRADED
- **Proactive replacement scheduling** — replace a flagged drive before it takes a vdev with it
- **Baseline capacity tracking** — know when to expand storage before you run out

---

## Two Exporters Required

| Exporter | Port | Purpose |
|---|---|---|
| `node_exporter` | 9100 | OS metrics, ZFS kernel stats, disk I/O, CPU, memory, filesystem usage |
| `smartctl_exporter` | 9633 | Per-drive SMART attribute values, overall SMART pass/fail status |

Both must be reachable from Prometheus at `10.0.10.80`.

---

## Option A: Deploy via TrueNAS Apps (Docker) — Preferred

TrueNAS SCALE includes a built-in app catalogue backed by Docker/Kubernetes. Custom apps can be deployed with full control over networking, mounts, and container flags. This is the recommended approach for SCALE installs.

### Step 1 — Deploy node-exporter as a Custom App

Navigate to **Apps → Discover Apps → Custom App** and configure:

**Image:** `prom/node-exporter:latest`

**Host network:** enabled (required — node-exporter must see the host's network interfaces and proc filesystem as the host sees them)

**Host PID namespace:** enabled (required for process-level metrics)

**Volume mounts:**

| Host path | Container path | Read-only |
|---|---|---|
| `/proc` | `/host/proc` | yes |
| `/sys` | `/host/sys` | yes |
| `/` | `/rootfs` | yes |
| `/var/lib/node_exporter/textfile_collector` | `/var/lib/node_exporter/textfile_collector` | no |

Create the textfile directory on TrueNAS first:
```bash
mkdir -p /var/lib/node_exporter/textfile_collector
```

**Container arguments (args):**
```
--path.procfs=/host/proc
--path.sysfs=/host/sys
--path.rootfs=/rootfs
--collector.zfs
--collector.diskstats
--collector.filesystem
--collector.hwmon
--collector.textfile
--collector.textfile.directory=/var/lib/node_exporter/textfile_collector
--collector.filesystem.mount-points-exclude=^/(dev|proc|sys|var/lib/docker/.+)($|/)
```

The `--collector.zfs` flag enables all `node_zfs_*` metrics. The `--collector.hwmon` flag picks up temperature sensors from the HBA and motherboard where available.

**Port:** expose container port `9100` on host port `9100`.

### Step 2 — Deploy smartctl-exporter as a Custom App

**Image:** `prometheuscommunit/smartctl_exporter:latest`

> Note: the image name uses `prometheuscommunit` (no trailing `y`) — this is the official community image name on Docker Hub.

**Privileged mode:** enabled, **or** add the host device `/dev` mounted at `/dev` — smartctl must be able to open raw device nodes to issue ATA/SCSI commands.

**Port:** expose container port `9633` on host port `9633`.

No additional flags are required for a basic deploy. The exporter auto-discovers all block devices and runs `smartctl --all` against each on a configurable interval (default: 60 seconds).

Optional environment variable to tune scrape interval:
```
SMARTCTL_EXPORTER_SCRAPE_INTERVAL=120s
```

### Step 3 — Add scrape targets to Prometheus

In your Prometheus config (`/srv/docker/appdata/prometheus/prometheus.yml`), add:

```yaml
scrape_configs:
  - job_name: truenas
    static_configs:
      - targets:
          - 10.0.10.80:9100   # node-exporter
          - 10.0.10.80:9633   # smartctl-exporter
        labels:
          host: truenas
```

---

## Option B: System-Level Install (TrueNAS CORE or No Apps Available)

Use this approach on TrueNAS CORE (FreeBSD-based) or if the Apps feature is unavailable.

### node-exporter

1. Download the latest Linux (or FreeBSD) binary from the [node-exporter releases page](https://github.com/prometheus/node_exporter/releases).
2. Copy the binary to `/usr/local/bin/node_exporter` and mark it executable:
   ```bash
   chmod +x /usr/local/bin/node_exporter
   ```
3. Create a service init script or use TrueNAS **System → Init/Shutdown Scripts** to run on post-init:
   ```bash
   /usr/local/bin/node_exporter \
     --collector.zfs \
     --collector.diskstats \
     --collector.filesystem \
     --collector.hwmon \
     --collector.textfile \
     --collector.textfile.directory=/var/lib/node_exporter/textfile_collector \
     --web.listen-address=:9100 &
   ```
4. Add the script to **Tasks → Init/Shutdown Scripts** with type **Post Init** so it survives reboots.

### smartctl-exporter

On FreeBSD (TrueNAS CORE), smartctl-exporter must be compiled from source or run via a Linux compatibility layer. An alternative is to write a cron-based textfile collector script that runs `smartctl` and writes `.prom` files into the textfile directory — node-exporter will then pick them up automatically.

---

## Verify the Endpoints

From any host that can reach TrueNAS (e.g., the Prometheus Docker host at `10.0.10.20`):

```bash
curl http://10.0.10.80:9100/metrics | head -20
curl http://10.0.10.80:9633/metrics | head -20
```

A successful response starts with `# HELP` and `# TYPE` comment lines followed by metric samples. A connection refused or timeout means the exporter is not running or a firewall rule is blocking the port.

---

## Key Metrics to Verify Are Present

After the exporters are running and Prometheus has scraped them at least once, confirm these metrics exist:

```promql
# ZFS pool state (should be 0 = ONLINE for all healthy pools)
node_zfs_zpool_state

# Checksum errors across all vdevs (should be 0; any non-zero warrants investigation)
node_zfs_vdev_checksum_errors_total

# Overall SMART pass/fail (1 = passed, 0 = failed)
smartctl_device_smart_status

# Reallocated sectors — replace drive if > 0
smartctl_device_attribute{attribute_name="Reallocated_Sector_Ct"}

# Drive temperature in Celsius
smartctl_device_attribute{attribute_name="Temperature_Celsius"}
```

---

## Critical SMART Attributes Reference

| Attribute | ID | Alarm Threshold | Meaning |
|---|---|---|---|
| Reallocated_Sector_Ct | 5 | > 0 | Drive hiding bad sectors behind spare area — replace soon |
| Current_Pending_Sector | 197 | > 0 | Unstable sectors awaiting reallocation — possible imminent failure |
| Offline_Uncorrectable | 198 | > 0 | Sectors that could not be corrected during offline scan — unrecoverable read errors |
| Spin_Retry_Count | 10 | > 0 | Motor struggled to spin up — indicates mechanical wear (spinning drives only) |
| Command_Timeout | 188 | Increasing | Drive stopped responding to commands within timeout — connection or electronics issue |
| Reallocated_Event_Count | 196 | > 0 | Number of reallocation events — complements attribute 5 |
| Temperature_Celsius | 194 | > 50°C warning, > 60°C critical | Sustained high temps accelerate platter and bearing wear |
| Power_On_Hours | 9 | > 40,000 h | Drive age in hours; 40,000 h ≈ 4.5 years of 24/7 operation |
| UDMA_CRC_Error_Count | 199 | Increasing | Errors on the SATA/SAS data bus — check cables, backplane connectors, HBA |

### Interpreting Raw vs. Normalized Values

SMART exposes each attribute in two forms:

- **Raw value** — the actual measured count or temperature. This is what `smartctl_exporter` surfaces and what you should alert on.
- **Normalized value** (1–253, vendor-defined) — a drive-internal score that decreases as the attribute degrades. Less reliable for alerting because the scale varies by manufacturer.

Always alert on **raw values**.

---

## ZFS Metrics Explained

### pool_state values (`node_zfs_zpool_state`)

ZFS reports pool state as an integer. The mapping:

| Value | State | Meaning |
|---|---|---|
| 0 | ONLINE | All vdevs healthy, pool fully operational |
| 1 | DEGRADED | One or more vdevs have failed/missing but pool is still accessible via redundancy |
| 2 | FAULTED | Pool has unrecoverable errors — data may be lost |
| 3 | OFFLINE | Pool has been taken offline manually |
| 4 | REMOVED | A device was physically removed |
| 5 | UNAVAIL | Pool cannot be imported — all top-level vdevs unavailable |

Alert on `node_zfs_zpool_state > 0` for any pool.

### vdev Error Counters

Three counters track data integrity at the vdev level:

- **`node_zfs_vdev_read_errors_total`** — I/O errors on reads. Any non-zero value on a healthy pool indicates a problem.
- **`node_zfs_vdev_write_errors_total`** — I/O errors on writes.
- **`node_zfs_vdev_checksum_errors_total`** — Data read back did not match the stored checksum. This is the most sensitive early-warning indicator because ZFS detects silent corruption that a conventional filesystem would pass through undetected.

Checksum errors on a single drive indicate that drive; checksum errors spread across many drives or the whole pool can indicate a failing HBA, bad cables, or ECC RAM issues.

### Scrub Completion

ZFS scrubs verify every block on disk and repair any correctable errors. Monitor:

- **`node_zfs_pool_scrub_errors_total`** — Errors found during the last scrub that could not be repaired.
- **`node_zfs_pool_scrub_repaired_bytes_total`** — Bytes repaired during scrub (non-zero means errors were found but fixed — acceptable if infrequent).

Schedule scrubs monthly at minimum (`zpool scrub <poolname>`). TrueNAS can be configured to run scrubs automatically under **Data Protection → Scrub Tasks**.
