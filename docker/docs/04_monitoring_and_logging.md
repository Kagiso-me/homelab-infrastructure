
# 05 — Monitoring & Logging
## Full Observability for the Docker Media Server

**Author:** Kagiso Tjeane
**Difficulty:** ⭐⭐⭐⭐⭐⭐☆☆☆☆ (6/10)
**Guide:** 05 of 06

> A platform that cannot be observed cannot be operated.
>
> At this point the media stack is running and traffic is flowing through Nginx Proxy Manager.
> But knowing containers are "up" is not the same as knowing the system is healthy. This guide
> adds the full visibility layer: host metrics, container telemetry, log aggregation, alert
> rules, and notification delivery.

---

## Why Monitoring Matters for the Media Stack

The failure modes of a media server are rarely dramatic. Services degrade quietly.

Without observability you only find out something is wrong when it stops working entirely:

- SABnzbd fills `/srv` to 100% and silently stops downloading — you notice when nothing has appeared in Jellyfin for three days
- Sonarr's download queue stalls because the connection to SABnzbd timed out — nothing failed, it just stopped
- Nginx Proxy Manager's Let's Encrypt cert expired — users get browser security warnings with no logged error you can easily find
- The nightly backup script failed because the NFS mount dropped — you discover this during a disaster recovery event

With a monitoring stack in place, the same scenarios look different:

- An alert fires 4 hours before `/srv` fills, triggered by a `predict_linear()` query
- A Grafana panel shows the Sonarr job queue depth climbing while download count stays flat
- NPM certificate expiry is visible as a metric days before it becomes a user-facing problem
- A `docker_backup_last_success_timestamp` metric goes stale at 25h and pages Slack before you go to bed

Observability turns reactive firefighting into proactive operations.

---

## Monitoring Architecture

```
Docker Host (10.0.10.20)
├── Node Exporter :9100 ──────────────────────► Prometheus :9090
├── cAdvisor :8080 ───────────────────────────► Prometheus
├── /var/lib/node_exporter/textfile_collector/ ► Prometheus (backup metrics)
└── Docker containers ──────► Promtail ───────► Loki :3100
                                                      │
                                                 Grafana :3000
                                                      │
                                               Alertmanager
                                                      │
                                       ┌──────────────┴──────────────┐
                                     Slack                      Webhook
                                #homelab-alerts            healthchecks.io
```

Two complementary pipelines carry all signal:

| Pipeline | What it carries | Components |
|----------|----------------|------------|
| Metrics | Numeric time-series (CPU %, bytes, counts) | Node Exporter, cAdvisor, textfile collector → Prometheus → Grafana |
| Logs | Raw log lines from containers and the host | Docker log files, /var/log → Promtail → Loki → Grafana |

| Component | Role | Port |
|-----------|------|------|
| Prometheus | Scrapes and stores time-series metrics | 9090 |
| Grafana | Visualises metrics and logs; manages alert rules | 3000 |
| Node Exporter | Exposes host-level metrics (CPU, memory, disk, network) | 9100 (host network) |
| cAdvisor | Exposes per-container resource metrics | 8080 |
| Loki | Stores and indexes log streams | 3100 |
| Promtail | Tails log files and ships them to Loki | — (internal) |
| Alertmanager | Routes alerts to Slack, webhooks, email | 9093 |

---

## Config Files in This Repo

All configuration files are committed to this repository under `docker/config/` and are
bind-mounted into their respective containers as read-only volumes. Do not write config
directly into the appdata directories — edit the repo files and restart the container.

| Repo path | Mounted into container at |
|-----------|--------------------------|
| `docker/config/prometheus/prometheus.yml` | `/etc/prometheus/prometheus.yml` |
| `docker/config/prometheus/alerts/*.yml` | `/etc/prometheus/alerts/` |
| `docker/config/loki/loki-config.yml` | `/etc/loki/config.yml` |
| `docker/config/promtail/promtail-config.yml` | `/etc/promtail/config.yml` |
| `docker/config/grafana/provisioning/` | `/etc/grafana/provisioning/` |

The bind mount blocks in `monitoring-stack.yml` for Prometheus look like this:

```yaml
volumes:
  - /srv/docker/appdata/prometheus:/prometheus
  - ../../docker/config/prometheus/prometheus.yml:/etc/prometheus/prometheus.yml:ro
  - ../../docker/config/prometheus/alerts:/etc/prometheus/alerts:ro
```

The path `../../docker/config/` is relative to `/srv/docker/stacks/` where the compose file lives.
Adjust the depth if your stacks directory is elsewhere.

---

## Step 1 — Create Directories

```bash
# Persistent data directories (written at runtime by each service)
sudo mkdir -p /srv/docker/appdata/prometheus/data
sudo mkdir -p /srv/docker/appdata/grafana
sudo mkdir -p /srv/docker/appdata/loki
sudo mkdir -p /srv/docker/appdata/alertmanager

# Grafana writes its SQLite DB as UID 472 — fix ownership now
sudo chown -R 472:472 /srv/docker/appdata/grafana

# Textfile collector directory (used by backup script to export custom metrics)
sudo mkdir -p /var/lib/node_exporter/textfile_collector
sudo chown root:root /var/lib/node_exporter/textfile_collector
sudo chmod 755 /var/lib/node_exporter/textfile_collector
```

---

## Step 2 — Prometheus Configuration

`docker/config/prometheus/prometheus.yml`

Prometheus scrapes metrics from Node Exporter, cAdvisor, Loki, and itself on a 15-second
interval. The `external_labels` block stamps every metric with the instance name so dashboards
remain readable if you ever aggregate multiple hosts into one Prometheus.

```yaml
global:
  scrape_interval: 15s
  evaluation_interval: 15s
  external_labels:
    host: docker-host
    environment: homelab

rule_files:
  - /etc/prometheus/alerts/*.yml

alerting:
  alertmanagers:
    - static_configs:
        - targets: ['alertmanager:9093']

scrape_configs:

  # Host-level metrics: CPU, memory, disk, network, NFS mounts, textfile collector
  - job_name: node
    static_configs:
      - targets: ['node-exporter:9100']
    relabel_configs:
      - source_labels: [__address__]
        target_label: instance
        replacement: 'docker-host (10.0.10.20)'

  # Per-container resource metrics from cAdvisor
  - job_name: cadvisor
    static_configs:
      - targets: ['cadvisor:8080']
    relabel_configs:
      - source_labels: [__address__]
        target_label: instance
        replacement: 'docker-host (10.0.10.20)'

  # Prometheus self-monitoring
  - job_name: prometheus
    static_configs:
      - targets: ['localhost:9090']

  # Loki internal metrics (ingestion rate, chunk count, etc.)
  - job_name: loki
    static_configs:
      - targets: ['loki:3100']
```

---

## Step 3 — Alert Rules

Alert rules live in `docker/config/prometheus/alerts/`. Prometheus evaluates them on every
`evaluation_interval` and forwards firing alerts to Alertmanager.

`docker/config/prometheus/alerts/docker-host.yml`

```yaml
groups:
  - name: docker-host
    interval: 60s
    rules:

      # Fires when /srv is more than 80% full
      - alert: DockerHostDiskFull
        expr: >
          (1 - node_filesystem_avail_bytes{mountpoint="/srv", fstype!="tmpfs"}
               / node_filesystem_size_bytes{mountpoint="/srv", fstype!="tmpfs"}) * 100 > 80
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Docker host disk /srv is {{ $value | humanize }}% full"
          description: "Free up space in /srv/docker/appdata or expand the volume. Run: du -sh /srv/docker/appdata/* | sort -rh"

      # Fires when NFS mount /mnt/media becomes unavailable (available bytes == 0)
      - alert: DockerNFSMountMissing
        expr: node_filesystem_avail_bytes{mountpoint=~"/mnt/.*"} == 0
        for: 2m
        labels:
          severity: critical
        annotations:
          summary: "NFS mount {{ $labels.mountpoint }} is unavailable"
          description: "Check TrueNAS is online and the export is healthy. Run: df -h {{ $labels.mountpoint }}"

      # Fires when host memory availability drops below 10%
      - alert: DockerHostMemoryHigh
        expr: >
          (1 - node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes) * 100 > 90
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Docker host memory is {{ $value | humanize }}% utilised"
          description: "Run: docker stats --no-stream | sort -k4 -rh"

      # Fires when CPU sustains above 85% for 15 minutes
      - alert: DockerHostCPUHigh
        expr: >
          100 - (avg(rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100) > 85
        for: 15m
        labels:
          severity: warning
        annotations:
          summary: "Docker host CPU is {{ $value | humanize }}% utilised"
          description: "Likely a runaway Jellyfin transcode or indexer rebuild. Check: docker stats"

  - name: backups
    interval: 300s
    rules:

      # Fires when the backup script has not run successfully in over 25 hours
      - alert: DockerBackupTooOld
        expr: time() - docker_backup_last_success_timestamp > 90000
        for: 0m
        labels:
          severity: critical
        annotations:
          summary: "Docker backup is {{ $value | humanize }}s old (threshold: 90000s / 25h)"
          description: "Check: sudo journalctl -u docker-backup -n 50 or cat /var/log/docker-backup.log"

      # Fires when backup file size is suspiciously small (under 10 MB)
      - alert: DockerBackupSizeSuspicious
        expr: docker_backup_size_bytes < 10485760
        for: 0m
        labels:
          severity: warning
        annotations:
          summary: "Docker backup archive is only {{ $value | humanizeBytes }} — expected >10MB"
          description: "The backup script may have produced an empty or corrupt archive."

  - name: containers
    interval: 60s
    rules:

      # Fires when a key media stack container disappears from cAdvisor
      - alert: DockerContainerDown
        expr: >
          absent(container_last_seen{name=~"jellyfin|sonarr|radarr|prowlarr|sabnzbd|nginx-proxy-manager"})
        for: 2m
        labels:
          severity: critical
        annotations:
          summary: "Container {{ $labels.name }} has disappeared"
          description: "Run: docker ps -a | grep {{ $labels.name }} && docker logs {{ $labels.name }} --tail 50"
```

---

## Step 4 — Loki Configuration

`docker/config/loki/loki-config.yml`

Loki stores log chunks on the local filesystem under the appdata directory. Retention is set
to 14 days, which is typically enough for debugging any incident that gets noticed within
two weeks. Increase `retention_period` if you need longer history.

```yaml
auth_enabled: false

server:
  http_listen_port: 3100
  grpc_listen_port: 9096

common:
  instance_addr: 127.0.0.1
  path_prefix: /loki
  storage:
    filesystem:
      chunks_directory: /loki/chunks
      rules_directory: /loki/rules
  replication_factor: 1
  ring:
    kvstore:
      store: inmemory

query_range:
  results_cache:
    cache:
      embedded_cache:
        enabled: true
        max_size_mb: 100

schema_config:
  configs:
    - from: 2024-01-01
      store: tsdb
      object_store: filesystem
      schema: v13
      index:
        prefix: index_
        period: 24h

limits_config:
  retention_period: 336h      # 14 days
  ingestion_rate_mb: 16
  ingestion_burst_size_mb: 32
  max_query_series: 5000

compactor:
  working_directory: /loki/compactor
  retention_enabled: true
  retention_delete_delay: 2h
```

---

## Step 5 — Promtail Configuration

`docker/config/promtail/promtail-config.yml`

Promtail ships logs from two sources: Docker container stdout/stderr (via the Docker socket
for service discovery) and host system logs under `/var/log`.

```yaml
server:
  http_listen_port: 9080
  grpc_listen_port: 0

positions:
  filename: /tmp/positions.yaml

clients:
  - url: http://loki:3100/loki/api/v1/push

scrape_configs:

  # Docker container logs — auto-labels by container name, image, compose service/project
  - job_name: docker
    docker_sd_configs:
      - host: unix:///var/run/docker.sock
        refresh_interval: 5s
    relabel_configs:
      - source_labels: ['__meta_docker_container_name']
        regex: '/(.*)'
        target_label: container
      - source_labels: ['__meta_docker_container_log_stream']
        target_label: stream
      - source_labels: ['__meta_docker_image_name']
        target_label: image
      - source_labels: ['__meta_docker_compose_service']
        target_label: service
      - source_labels: ['__meta_docker_compose_project']
        target_label: compose_project
      - target_label: app
        replacement: media-stack

  # Host system logs (/var/log/*.log)
  - job_name: system
    static_configs:
      - targets:
          - localhost
        labels:
          job: system
          host: docker-host
          __path__: /var/log/*.log

  # Auth log (SSH logins, sudo, PAM) — separate job for easier alerting
  - job_name: auth
    static_configs:
      - targets:
          - localhost
        labels:
          job: auth
          host: docker-host
          __path__: /var/log/auth.log
```

---

## Step 6 — Alertmanager Configuration

Alertmanager receives firing alerts from Prometheus and routes them to the configured
receivers. This example routes all alerts to a Slack webhook.

Create `/srv/docker/appdata/alertmanager/alertmanager.yml`:

```yaml
global:
  resolve_timeout: 5m
  slack_api_url: 'https://hooks.slack.com/services/YOUR/WEBHOOK/URL'

route:
  group_by: ['alertname', 'severity']
  group_wait: 30s
  group_interval: 5m
  repeat_interval: 4h
  receiver: slack-homelab

  routes:
    - match:
        severity: critical
      receiver: slack-homelab
      repeat_interval: 1h

receivers:
  - name: slack-homelab
    slack_configs:
      - channel: '#homelab-alerts'
        send_resolved: true
        title: '{{ .Status | toUpper }} — {{ .GroupLabels.alertname }}'
        text: |
          {{ range .Alerts }}
          *Alert:* {{ .Labels.alertname }}
          *Severity:* {{ .Labels.severity }}
          *Summary:* {{ .Annotations.summary }}
          *What to do:* {{ .Annotations.description }}
          {{ end }}
        color: '{{ if eq .Status "firing" }}danger{{ else }}good{{ end }}'

  # healthchecks.io integration for backup freshness
  - name: healthchecks
    webhook_configs:
      - url: 'https://hc-ping.com/YOUR-UUID-HERE'
        send_resolved: false

inhibit_rules:
  # Suppress warnings when a critical alert is already firing for the same instance
  - source_match:
      severity: critical
    target_match:
      severity: warning
    equal: ['instance']
```

---

## Step 7 — Grafana Provisioning

`docker/config/grafana/provisioning/datasources/datasources.yml`

Grafana auto-provisions data sources from this file on startup. No manual UI configuration
is needed after deploying the stack.

```yaml
apiVersion: 1

datasources:
  - name: Prometheus
    type: prometheus
    access: proxy
    url: http://prometheus:9090
    isDefault: true
    editable: false
    jsonData:
      timeInterval: '15s'

  - name: Loki
    type: loki
    access: proxy
    url: http://loki:3100
    editable: false
    jsonData:
      maxLines: 1000
```

---

## Step 8 — Deploy the Monitoring Stack

```bash
# Create the shared monitoring network (skip if it already exists)
docker network create monitoring-net

# Deploy all six services
cd /srv/docker/stacks
docker compose -f monitoring-stack.yml up -d

# Verify all six started and are healthy
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" \
  | grep -E "prometheus|grafana|node-exporter|cadvisor|loki|promtail|alertmanager"
```

Expected output (all containers should show `Up` or `Up (healthy)`):

```
prometheus       Up 2 minutes (healthy)   0.0.0.0:9090->9090/tcp
grafana          Up 2 minutes (healthy)   0.0.0.0:3000->3000/tcp
node-exporter    Up 2 minutes             (host network)
cadvisor         Up 2 minutes (healthy)   0.0.0.0:8080->8080/tcp
loki             Up 2 minutes (healthy)   0.0.0.0:3100->3100/tcp
promtail         Up 2 minutes
alertmanager     Up 2 minutes             0.0.0.0:9093->9093/tcp
```

The `monitoring-stack.yml` compose file should look like this:

```yaml
networks:
  monitoring-net:
    external: true   # Created above with docker network create

services:

  prometheus:
    image: prom/prometheus:latest
    container_name: prometheus
    command:
      - '--config.file=/etc/prometheus/prometheus.yml'
      - '--storage.tsdb.path=/prometheus'
      - '--storage.tsdb.retention.time=15d'
      - '--storage.tsdb.retention.size=10GB'
      - '--web.enable-lifecycle'
    volumes:
      - /srv/docker/appdata/prometheus/data:/prometheus
      - ../../docker/config/prometheus/prometheus.yml:/etc/prometheus/prometheus.yml:ro
      - ../../docker/config/prometheus/alerts:/etc/prometheus/alerts:ro
    ports:
      - "9090:9090"
    networks:
      - monitoring-net
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "wget", "-qO-", "http://localhost:9090/-/healthy"]
      interval: 30s
      timeout: 10s
      retries: 5

  grafana:
    image: grafana/grafana:latest
    container_name: grafana
    environment:
      - TZ=Africa/Johannesburg
      - GF_SECURITY_ADMIN_USER=admin
      - GF_SECURITY_ADMIN_PASSWORD=changeme    # Change immediately after first login
      - GF_USERS_ALLOW_SIGN_UP=false
      - GF_SERVER_ROOT_URL=http://10.0.10.20:3000
      - GF_LOG_LEVEL=warn
    volumes:
      - /srv/docker/appdata/grafana:/var/lib/grafana
      - ../../docker/config/grafana/provisioning:/etc/grafana/provisioning:ro
    ports:
      - "3000:3000"
    networks:
      - monitoring-net
    depends_on:
      - prometheus
      - loki
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "wget", "-qO-", "http://localhost:3000/api/health"]
      interval: 30s
      timeout: 10s
      retries: 5

  node-exporter:
    image: prom/node-exporter:latest
    container_name: node-exporter
    command:
      - '--path.rootfs=/host'
      - '--collector.filesystem.mount-points-exclude=^/(sys|proc|dev|host|etc)($$|/)'
      - '--collector.textfile.directory=/var/lib/node_exporter/textfile_collector'
    pid: host
    network_mode: host    # Must use host network to see real interfaces + NFS mounts
    volumes:
      - /:/host:ro,rslave
      - /var/lib/node_exporter/textfile_collector:/var/lib/node_exporter/textfile_collector:ro
    restart: unless-stopped

  cadvisor:
    image: gcr.io/cadvisor/cadvisor:latest
    container_name: cadvisor
    privileged: true
    command:
      - '--port=8080'
      - '--housekeeping_interval=10s'
      - '--docker_only=true'
    devices:
      - /dev/kmsg:/dev/kmsg
    volumes:
      - /:/rootfs:ro
      - /var/run:/var/run:ro
      - /sys:/sys:ro
      - /var/lib/docker:/var/lib/docker:ro
      - /cgroup:/cgroup:ro
    ports:
      - "8080:8080"
    networks:
      - monitoring-net
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "wget", "-qO-", "http://localhost:8080/healthz"]
      interval: 30s
      timeout: 10s
      retries: 5

  loki:
    image: grafana/loki:latest
    container_name: loki
    command: -config.file=/etc/loki/config.yml
    volumes:
      - /srv/docker/appdata/loki:/loki
      - ../../docker/config/loki/loki-config.yml:/etc/loki/config.yml:ro
    ports:
      - "3100:3100"
    networks:
      - monitoring-net
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "wget", "-qO-", "http://localhost:3100/ready"]
      interval: 30s
      timeout: 10s
      retries: 5
      start_period: 30s

  promtail:
    image: grafana/promtail:latest
    container_name: promtail
    command: -config.file=/etc/promtail/config.yml
    volumes:
      - /var/log:/var/log:ro
      - /var/lib/docker/containers:/var/lib/docker/containers:ro
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - ../../docker/config/promtail/promtail-config.yml:/etc/promtail/config.yml:ro
    networks:
      - monitoring-net
    restart: unless-stopped

  alertmanager:
    image: prom/alertmanager:latest
    container_name: alertmanager
    command:
      - '--config.file=/etc/alertmanager/alertmanager.yml'
      - '--storage.path=/alertmanager'
    volumes:
      - /srv/docker/appdata/alertmanager/alertmanager.yml:/etc/alertmanager/alertmanager.yml:ro
      - /srv/docker/appdata/alertmanager/data:/alertmanager
    ports:
      - "9093:9093"
    networks:
      - monitoring-net
    restart: unless-stopped
```

> **Note on `node-exporter`:** It runs with `network_mode: host` and `pid: host` so it can
> see the real host network interfaces, NFS mounts, and process table — not Docker's namespaced
> view. This means it cannot use the `monitoring-net` Docker network to reach Prometheus.
> Instead, Prometheus scrapes `node-exporter:9100` by using the container name only when
> node-exporter is on the same bridge network. Because node-exporter uses host networking,
> Prometheus must use the host IP `10.0.10.20:9100` or `host-gateway:9100` in its scrape
> config, or both must share the host network. The config above uses `node-exporter:9100`
> which works when Prometheus has a `host-gateway` alias or both containers are on the same
> machine. If Prometheus shows the node target as DOWN, change the target to `10.0.10.20:9100`.

---

## Step 9 — Grafana Initial Setup

### First Login

Open `http://10.0.10.20:3000`

Default credentials: `admin` / `admin` (or whatever was set in `GF_SECURITY_ADMIN_PASSWORD`).

**Change the password immediately.** Grafana stores dashboards, alert state, and contact
point secrets. Treat it like any other administrative interface.

### Verify Auto-Provisioned Data Sources

Navigate to **Connections → Data Sources**. You should see:

- **Prometheus** — click it, scroll to the bottom, click **Save & Test** — expect "Data source is working"
- **Loki** — same process — expect "Data source connected and labels found"

If either shows an error, check that the container names in the data source URLs match the
running container names (`docker ps`).

### Import Community Dashboards

Navigate to **Dashboards → New → Import**, enter the dashboard ID, click **Load**, select
the correct data source, and click **Import**.

| Dashboard | ID | Data source | What it shows |
|-----------|-----|-------------|---------------|
| Node Exporter Full | 1860 | Prometheus | CPU, memory, disk I/O, network, all mounts for the Docker host |
| Docker Container Monitoring | 893 | Prometheus | Per-container CPU, memory, network, block I/O |
| Docker Container & Host Metrics | 10619 | Prometheus | Alternative container view with host context |
| Loki Dashboard | 13639 | Loki | Log volume, error rate, log explorer by container |
| cAdvisor Exporter | 14282 | Prometheus | Detailed container resource breakdown |

The **Node Exporter Full** (1860) dashboard is the most immediately useful — open it after
import and verify you can see real CPU, memory, and disk data for the host.

---

## Step 10 — What Each Metric Source Collects

### Node Exporter — Host Metrics

Node Exporter exposes hundreds of host-level metrics. These are the ones that matter most
for operating a media server:

| Metric | Example PromQL query | Alert threshold |
|--------|---------------------|----------------|
| CPU usage % | `100 - (avg(rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)` | >85% for 15m |
| Memory used % | `(1 - node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes) * 100` | >90% for 5m |
| Disk usage /srv | `(1 - node_filesystem_avail_bytes{mountpoint="/srv"} / node_filesystem_size_bytes{mountpoint="/srv"}) * 100` | >80% |
| Disk bytes free /srv | `node_filesystem_avail_bytes{mountpoint="/srv"}` | <50GB = start cleaning |
| NFS mount /mnt/media | `node_filesystem_avail_bytes{mountpoint="/mnt/media"}` | ==0 means mount lost |
| Network receive | `rate(node_network_receive_bytes_total{device="eth0"}[5m]) * 8` | — (trend monitoring) |
| Network transmit | `rate(node_network_transmit_bytes_total{device="eth0"}[5m]) * 8` | — (trend monitoring) |
| Load average | `node_load1` | >number of vCPUs |
| Backup age | `time() - docker_backup_last_success_timestamp` | >90000s = >25h |

### cAdvisor — Container Metrics

cAdvisor exposes per-container resource consumption. The `name` label contains the container name.

| Metric | Example PromQL query | What it tells you |
|--------|---------------------|-------------------|
| Container CPU % | `rate(container_cpu_usage_seconds_total{name="jellyfin"}[5m]) * 100` | Whether Jellyfin is transcoding |
| Container memory | `container_memory_usage_bytes{name="sonarr"}` | RSS memory for each service |
| Container memory limit | `container_spec_memory_limit_bytes{name!=""}` | Whether limits are set |
| Container restarts | `rate(container_start_time_seconds{name!=""}[1h])` | Crash-looping containers |
| Container network in | `rate(container_network_receive_bytes_total{name="sabnzbd"}[5m])` | Download bandwidth |
| Container network out | `rate(container_network_transmit_bytes_total{name="sabnzbd"}[5m])` | Upload / API traffic |
| Container disk reads | `rate(container_fs_reads_bytes_total{name="jellyfin"}[5m])` | Disk read rate |

### Textfile Collector — Backup Metrics

The backup script writes `.prom` files to `/var/lib/node_exporter/textfile_collector/`.
Node Exporter reads them and exposes the metrics to Prometheus automatically.

| Metric | Written by | Example PromQL query | Alert threshold |
|--------|-----------|---------------------|----------------|
| `docker_backup_last_success_timestamp` | `backup_docker.sh` | `time() - docker_backup_last_success_timestamp` | >90000s (25h) |
| `docker_backup_size_bytes` | `backup_docker.sh` | `docker_backup_size_bytes` | <10MB = suspicious |
| `docker_backup_duration_seconds` | `backup_docker.sh` | trend over time | sudden spike = investigate |

---

## Step 11 — Key Prometheus Queries to Bookmark

Open Prometheus at `http://10.0.10.20:9090` and use the **Graph** tab to run these queries.
They are also useful as the basis for Grafana panels.

```promql
# Which containers are consuming the most memory right now?
topk(5, container_memory_usage_bytes{name!=""})

# Is the NFS /mnt/media mount healthy? (non-zero = healthy)
node_filesystem_avail_bytes{mountpoint=~"/mnt/.*"}

# How many hours until /srv fills at the current rate?
predict_linear(node_filesystem_avail_bytes{mountpoint="/srv"}[6h], 3600 * 24) /
  node_filesystem_size_bytes{mountpoint="/srv"} * 100

# Container restart rate over the last hour (crashes per hour per container)
rate(container_start_time_seconds{name!=""}[1h]) * 3600

# Current CPU load by container, sorted highest first
sort_desc(
  sum by (name) (rate(container_cpu_usage_seconds_total{name!=""}[5m])) * 100
)

# How old is the most recent backup, in hours?
(time() - docker_backup_last_success_timestamp) / 3600

# Memory pressure: how much memory headroom does the host have?
node_memory_MemAvailable_bytes / 1024 / 1024 / 1024

# Network bandwidth currently being consumed by SABnzbd (Mbps)
rate(container_network_receive_bytes_total{name="sabnzbd"}[1m]) * 8 / 1000000

# Which containers are currently running? (container present in cAdvisor)
count by (name) (container_last_seen{name!=""})

# Disk I/O read rate for all containers (top consumers)
topk(5, rate(container_fs_reads_bytes_total{name!=""}[5m]))
```

---

## Step 12 — Log Monitoring with Loki

Open the Grafana Explore view, select the **Loki** data source, and run these LogQL queries.

### Essential LogQL Queries

```logql
# All log lines from any container in the media stack (last 1h)
{app="media-stack"}

# All error-level lines from any container
{app="media-stack"} |= "error"

# Failed download events (Sonarr/Radarr)
{container=~"sonarr|radarr"} |= "failed"
| line_format "{{.container}}: {{.line}}"

# SABnzbd warnings and errors
{container="sabnzbd"} |~ "(WARNING|ERROR)"

# Nginx Proxy Manager 4xx responses (access denied, not found)
{container="nginx-proxy-manager"} |= " 40"

# NPM certificate renewal activity
{container="nginx-proxy-manager"} |= "certificate"

# SSH failed password attempts on the host
{job="auth"} |= "Failed password"
| regexp `from (?P<ip>\S+) port`
| line_format "Failed login from: {{.ip}}"

# All backup script log output
{job="system"} |= "backup"

# Jellyfin transcoding activity (useful for diagnosing performance issues)
{container="jellyfin"} |= "transcode"

# Any container that has logged "OOMKilled" or "killed" (out of memory)
{app="media-stack"} |~ "(OOMKilled|killed|kill)"

# Promtail delivery errors to Loki (if logs are missing)
{container="promtail"} |= "error"
```

### Log Volume Rate Query

This query gives you a rate-of-log-lines-per-second by container, useful for spotting
a container that is suddenly flooding logs (often a symptom of a crash loop):

```logql
sum by (container) (
  rate({app="media-stack"}[5m])
)
```

---

## Step 13 — Alert Rules Overview

All alert rules live in `docker/config/prometheus/alerts/`. This table summarises what
is configured and what the correct first response is:

| Alert | Condition | Severity | First response |
|-------|-----------|----------|----------------|
| `DockerBackupTooOld` | Last backup >25h old | critical | `sudo journalctl -u docker-backup -n 50` |
| `DockerContainerDown` | jellyfin/sonarr/etc absent from cAdvisor | critical | `docker ps -a`, then `docker logs <name> --tail 50` |
| `DockerHostDiskFull` | `/srv` >80% full | warning | `du -sh /srv/docker/appdata/* \| sort -rh` |
| `DockerNFSMountMissing` | `/mnt/media` unavailable | critical | `df -h /mnt/media`; check TrueNAS status |
| `DockerHostMemoryHigh` | Memory >90% for 5m | warning | `docker stats --no-stream \| sort -k4 -rh` |
| `DockerHostCPUHigh` | CPU >85% for 15m | warning | `docker stats --no-stream` |
| `DockerBackupSizeSuspicious` | Backup archive <10MB | warning | Inspect `/srv/docker/backups/` manually |

### Alert Routing

All critical alerts repeat every 1 hour until resolved. Warning alerts repeat every 4 hours.
The Alertmanager inhibition rule suppresses warning alerts when a critical alert is already
firing for the same instance, preventing alert fatigue during a major incident.

---

## Step 14 — Textfile Collector Setup

Node Exporter's textfile collector allows any script to export custom metrics by writing
`.prom` format files into a watched directory. This is how backup success/failure timestamps
reach Prometheus without running a separate exporter.

```bash
# Create and secure the directory
sudo mkdir -p /var/lib/node_exporter/textfile_collector
sudo chown root:root /var/lib/node_exporter/textfile_collector
sudo chmod 755 /var/lib/node_exporter/textfile_collector

# Run a backup manually to verify the metrics file gets written
sudo /srv/scripts/backup_docker.sh

# Check the written metrics
cat /var/lib/node_exporter/textfile_collector/docker_backup.prom
```

Expected content of `docker_backup.prom`:

```
# HELP docker_backup_last_success_timestamp Unix timestamp of last successful backup
# TYPE docker_backup_last_success_timestamp gauge
docker_backup_last_success_timestamp 1718000000

# HELP docker_backup_size_bytes Size in bytes of the most recent backup archive
# TYPE docker_backup_size_bytes gauge
docker_backup_size_bytes 524288000

# HELP docker_backup_duration_seconds Duration in seconds of the last backup run
# TYPE docker_backup_duration_seconds gauge
docker_backup_duration_seconds 142
```

Verify the metric is visible in Prometheus:

```
http://10.0.10.20:9090/graph?g0.expr=docker_backup_last_success_timestamp
```

If the metric does not appear, check that the node-exporter compose command includes
`--collector.textfile.directory=/var/lib/node_exporter/textfile_collector`.

---

## Step 15 — Complete Verification Procedure

Work through each of the following in order. Do not move on to Guide 06 until all
verification steps pass.

### 1. All containers running

```bash
docker ps --format "table {{.Names}}\t{{.Status}}" \
  | grep -E "prometheus|grafana|node-exporter|cadvisor|loki|promtail|alertmanager"
```

All seven lines must show `Up` (with `healthy` for those that have a healthcheck).

### 2. Prometheus targets all UP

Open `http://10.0.10.20:9090/targets`

All four jobs must show state `UP`:
- `node` (1/1 up)
- `cadvisor` (1/1 up)
- `prometheus` (1/1 up)
- `loki` (1/1 up)

If a target shows `DOWN`, click on its error message. Common causes:

| Error | Cause |
|-------|-------|
| `dial tcp: no route to host` | Container not on the same Docker network |
| `connection refused` | Container not yet started or crashed |
| `context deadline exceeded` | Container overloaded or wrong port |

### 3. Prometheus receiving node metrics

In the Prometheus UI, query:

```
node_memory_MemTotal_bytes
```

This should return a single value showing the host's total RAM (e.g. `16977346560` for 16 GB).
If it returns no results, node-exporter is not being scraped.

### 4. Prometheus receiving backup metrics

```
docker_backup_last_success_timestamp
```

This must return a result. If it does not:
- Verify the backup script has been run at least once
- Verify the `.prom` file exists: `ls -la /var/lib/node_exporter/textfile_collector/`
- Verify the textfile directory is mounted into the node-exporter container

### 5. Grafana data sources connected

In Grafana, navigate to **Connections → Data Sources**.
Click each data source and run **Save & Test**.
Both Prometheus and Loki must show a green success message.

### 6. Grafana Node Exporter dashboard showing real data

Open the **Node Exporter Full** dashboard (ID 1860).
Set the time range to **Last 5 minutes**.
CPU usage, memory used, and filesystem usage panels must all show values (not "No data").

### 7. Loki receiving container logs

In Grafana **Explore**, select the Loki data source and run:

```logql
{app="media-stack"}
```

Log lines from running containers must appear within a few seconds.

If no results appear:
- Check Promtail is running: `docker logs promtail --tail 30`
- Verify Promtail can reach Loki: look for "level=info component=client" lines in promtail logs
- Verify Docker socket is mounted: `docker exec promtail ls /var/run/docker.sock`

### 8. Test alert delivery

Temporarily create a test alert rule in Grafana (**Alerting → Alert Rules → New Alert Rule**)
with a condition that is immediately true (e.g. `vector(1) > 0`), wait for it to fire, and
verify the notification arrives in Slack.

Delete the test rule after confirming delivery.

---

## Service Access Reference

| Service | URL | Credentials |
|---------|-----|------------|
| Grafana | `http://10.0.10.20:3000` | admin / (set in compose env) |
| Prometheus | `http://10.0.10.20:9090` | None |
| Alertmanager | `http://10.0.10.20:9093` | None |
| cAdvisor | `http://10.0.10.20:8080` | None |
| Loki API | `http://10.0.10.20:3100` | None |
| Node Exporter metrics | `http://10.0.10.20:9100/metrics` | None (LAN only) |

> **Security:** Prometheus, cAdvisor, Node Exporter, Loki, and Alertmanager expose
> sensitive system information with no authentication. Never proxy them externally.
> Only Grafana should be accessible via Nginx Proxy Manager if you need remote access.

---

## Troubleshooting Reference

| Symptom | Likely cause | Resolution |
|---------|-------------|------------|
| Prometheus target DOWN | Container not reachable by name | Verify both containers share `monitoring-net`; check `docker network inspect monitoring-net` |
| Node Exporter shows wrong filesystems | Mount-points-exclude regex too narrow | Adjust `--collector.filesystem.mount-points-exclude` flag |
| Node Exporter missing NFS mounts | Host-side: NFS mount not present | `df -h /mnt/media` on the host; remount if missing |
| Loki `ready` returns 503 | Config YAML syntax error | `docker logs loki --tail 30`; validate YAML |
| Promtail not shipping Docker logs | Docker socket not mounted | Verify `/var/run/docker.sock` volume in compose file |
| Grafana shows "No data" | Data source URL uses localhost | Use container names in data source URLs, not `localhost` |
| cAdvisor shows no container metrics | Privilege or cgroup mount issue | Ensure `privileged: true` and all cgroup volumes are present |
| Backup metric stale in Prometheus | Textfile directory not mounted | Check node-exporter container volume: `docker inspect node-exporter \| grep textfile` |
| Alertmanager not receiving alerts | Prometheus alerting config wrong | Check `http://10.0.10.20:9090/config` for alertmanager URL |
| Slack not receiving alerts | Wrong webhook URL | Test with: `curl -X POST -H 'Content-type: application/json' --data '{"text":"test"}' <webhook_url>` |

---

## Exit Criteria

This guide is complete when all of the following are true:

```
✓ All 7 monitoring services running (prometheus, grafana, node-exporter, cadvisor, loki, promtail, alertmanager)
✓ Prometheus targets page: node, cadvisor, prometheus, loki all showing UP
✓ Grafana data sources: Prometheus and Loki both show "Data source is working"
✓ Node Exporter Full dashboard (1860) showing real CPU, memory, disk data
✓ Docker Container Metrics dashboard (893) showing per-container resource data
✓ Loki receiving logs — Explore query {app="media-stack"} returns results
✓ Backup metrics visible: docker_backup_last_success_timestamp present in Prometheus
✓ At least one test alert fired and notification received in Slack
✓ NFS mount metrics present: node_filesystem_avail_bytes for /mnt/media shows a value
✓ Textfile collector directory exists at /var/lib/node_exporter/textfile_collector
```

---

## Navigation

| | Guide |
|---|---|
| ← Previous | [04 — Media Stack & Reverse Proxy](./03_media_stack_and_reverse_proxy.md) |
| Current | **05 — Monitoring & Logging** |
| → Next | [06 — Backups & Disaster Recovery](./05_backups_and_disaster_recovery.md) |
