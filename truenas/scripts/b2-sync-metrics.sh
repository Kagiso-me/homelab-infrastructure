#!/usr/bin/env bash
# b2-sync-metrics.sh
# Writes Backblaze B2 cloud sync metrics to the node_exporter textfile
# collector so they appear in Prometheus and the Grafana backup dashboard.
#
# Metrics produced (same schema as other backup scripts):
#   backup_job_status{job="truenas-b2-sync"}             1=success, 0=failure
#   backup_last_success_timestamp{job="truenas-b2-sync"} unix timestamp
#   b2_bucket_size_bytes{bucket="..."}                   total bytes in bucket
#   b2_bucket_file_count{bucket="..."}                   file count in bucket
#
# Deploy:
#   sudo cp b2-sync-metrics.sh /usr/local/bin/b2-sync-metrics.sh
#   sudo chmod 750 /usr/local/bin/b2-sync-metrics.sh
#
# Config file: /etc/b2-sync-metrics.conf (chmod 600, owned by root)
#   TRUENAS_API_KEY=<api-key-with-read-access>
#   B2_RCLONE_REMOTE=b2remote          # rclone remote name for B2
#   B2_BUCKET=homelab-truenas-backup   # B2 bucket name
#   TASK_PATTERN=[Bb]ackblaze          # regex matching the Cloud Sync task description
#   TEXTFILE_DIR=/var/lib/node_exporter/textfile_collector
#
# Schedule (TrueNAS cron task — run at 05:00, after the 04:00 B2 sync):
#   Command: /usr/local/bin/b2-sync-metrics.sh
#   Schedule: 0 5 * * *
#   Run as: root
#
# rclone remote setup (run once as root on TrueNAS):
#   rclone config create b2remote b2 account <keyID> key <appKey>
#   rclone size b2remote:homelab-truenas-backup --json   # verify

set -euo pipefail

# ── Config defaults (override via /etc/b2-sync-metrics.conf) ────────────────
TRUENAS_API_KEY=""
B2_RCLONE_REMOTE="b2remote"
B2_BUCKET="homelab-truenas-backup"
TASK_PATTERN="[Bb]ackblaze"
TEXTFILE_DIR="/var/lib/node_exporter/textfile_collector"

CREDS_FILE="/etc/b2-sync-metrics.conf"
# shellcheck source=/dev/null
[[ -f "$CREDS_FILE" ]] && source "$CREDS_FILE"

METRIC_FILE="${TEXTFILE_DIR}/b2_sync.prom"
TMP_FILE="${METRIC_FILE}.tmp.$$"
trap 'rm -f "$TMP_FILE"' EXIT

mkdir -p "${TEXTFILE_DIR}"

# ── Defaults (overwritten by successful queries below) ──────────────────────
SYNC_STATUS=0
LAST_SUCCESS_TS=0
B2_SIZE_BYTES=-1
B2_FILE_COUNT=-1

# ── TrueNAS API: Cloud Sync task status ─────────────────────────────────────
if [[ -z "$TRUENAS_API_KEY" ]]; then
  echo "WARNING: TRUENAS_API_KEY not set in ${CREDS_FILE} — skipping API query" >&2
else
  API_RESPONSE=$(curl -sf \
    -H "Authorization: Bearer ${TRUENAS_API_KEY}" \
    "http://localhost/api/v2.0/cloudsync" 2>/dev/null) || true

  if [[ -n "$API_RESPONSE" ]]; then
    TASK=$(echo "$API_RESPONSE" | \
      jq -r --arg pat "$TASK_PATTERN" \
      '[.[] | select(.description | test($pat))] | first // empty')

    if [[ -z "$TASK" ]]; then
      echo "WARNING: No Cloud Sync task matching '${TASK_PATTERN}' found" >&2
    else
      JOB_STATE=$(echo "$TASK" | jq -r '.job.state // "UNKNOWN"')
      JOB_FINISHED=$(echo "$TASK" | jq -r '.job.time_finished // ""')

      if [[ "$JOB_STATE" == "SUCCESS" ]]; then
        SYNC_STATUS=1
        if [[ -n "$JOB_FINISHED" ]] && [[ "$JOB_FINISHED" != "null" ]]; then
          # TrueNAS returns ISO 8601; date -d handles it on TrueNAS Scale (Debian)
          LAST_SUCCESS_TS=$(date -d "$JOB_FINISHED" +%s 2>/dev/null || echo 0)
        fi
      else
        echo "INFO: Last sync state='${JOB_STATE}', preserving previous last_success_timestamp" >&2
        # Preserve the last known good timestamp from the existing metric file
        LAST_SUCCESS_TS=$(grep -oP \
          'backup_last_success_timestamp\{job="truenas-b2-sync"\} \K[0-9]+' \
          "$METRIC_FILE" 2>/dev/null || echo 0)
      fi
    fi
  else
    echo "WARNING: Empty response from TrueNAS API" >&2
  fi
fi

# ── rclone: B2 bucket size and file count ────────────────────────────────────
# rclone size lists all objects in the bucket; on large buckets this may take
# 1-3 minutes. Schedule this script to run well after the sync completes.
if command -v rclone &>/dev/null; then
  RCLONE_OUTPUT=$(rclone size "${B2_RCLONE_REMOTE}:${B2_BUCKET}" \
    --json --fast-list 2>/dev/null) || RCLONE_OUTPUT='{}'
  B2_SIZE_BYTES=$(echo "$RCLONE_OUTPUT" | jq -r '.bytes  // -1')
  B2_FILE_COUNT=$(echo "$RCLONE_OUTPUT" | jq -r '.count  // -1')
else
  echo "WARNING: rclone not found — bucket stats will be -1" >&2
fi

# ── Write Prometheus metrics ─────────────────────────────────────────────────
cat > "$TMP_FILE" << PROM
# HELP backup_job_status Status of the last Backblaze B2 cloud sync (1=success, 0=failure)
# TYPE backup_job_status gauge
backup_job_status{job="truenas-b2-sync"} ${SYNC_STATUS}
# HELP backup_last_success_timestamp Unix timestamp of the last successful B2 sync
# TYPE backup_last_success_timestamp gauge
backup_last_success_timestamp{job="truenas-b2-sync"} ${LAST_SUCCESS_TS}
# HELP b2_bucket_size_bytes Total size of all files currently stored in the Backblaze B2 bucket
# TYPE b2_bucket_size_bytes gauge
b2_bucket_size_bytes{bucket="${B2_BUCKET}"} ${B2_SIZE_BYTES}
# HELP b2_bucket_file_count Number of files currently stored in the Backblaze B2 bucket
# TYPE b2_bucket_file_count gauge
b2_bucket_file_count{bucket="${B2_BUCKET}"} ${B2_FILE_COUNT}
PROM

mv "$TMP_FILE" "$METRIC_FILE"
echo "B2 metrics written — status=${SYNC_STATUS} size=${B2_SIZE_BYTES} files=${B2_FILE_COUNT}"
