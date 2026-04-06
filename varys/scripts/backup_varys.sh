#!/usr/bin/env bash
# =============================================================================
# backup_varys.sh - Control-hub key material backup
#
# Backs up varys operator credentials and kubeconfig to a TrueNAS NFS share.
# The archive is GPG-encrypted before being written to disk because it contains
# the age private key used for SOPS.
#
# Deploy to: /usr/local/bin/varys-backup.sh
# Schedule:  0 1 * * * root /usr/local/bin/varys-backup.sh
# =============================================================================

set -euo pipefail

NFS_SERVER="10.0.10.80"
NFS_SHARE="/mnt/archive/backups"
MOUNT_POINT="/mnt/backup_varys"
BACKUP_DIR="${MOUNT_POINT}/varys"
RETENTION_DAYS=30
TIMESTAMP=$(date +"%Y-%m-%d_%H%M%S")
ARCHIVE_NAME="varys_backup_${TIMESTAMP}.tar.gz.gpg"
LOG_FILE="/var/log/varys-backup.log"
PASSPHRASE_FILE="/root/.varys_backup_passphrase"
TEXTFILE_DIR="/var/lib/node_exporter/textfile_collector"
TEXTFILE_METRIC="${TEXTFILE_DIR}/varys_backup.prom"
JOB="varys-keys"

START_TIME=$(date +%s)

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "${LOG_FILE}"
}

write_metrics() {
  local status="$1" ts="$2" size="$3" duration="$4" failures="$5"
  mkdir -p "${TEXTFILE_DIR}"
  local tmp
  tmp=$(mktemp "${TEXTFILE_METRIC}.XXXXXX")
  cat > "${tmp}" <<METRICS
# HELP backup_job_status 1 = last run succeeded, 0 = failed.
# TYPE backup_job_status gauge
backup_job_status{job="${JOB}"} ${status}
# HELP backup_last_success_timestamp Unix timestamp of last successful backup.
# TYPE backup_last_success_timestamp gauge
backup_last_success_timestamp{job="${JOB}"} ${ts}
# HELP backup_size_bytes Size of last backup archive in bytes.
# TYPE backup_size_bytes gauge
backup_size_bytes{job="${JOB}"} ${size}
# HELP backup_duration_seconds Duration of last backup run in seconds.
# TYPE backup_duration_seconds gauge
backup_duration_seconds{job="${JOB}"} ${duration}
# HELP backup_failures_total Cumulative count of failed backup runs.
# TYPE backup_failures_total counter
backup_failures_total{job="${JOB}"} ${failures}
METRICS
  mv "${tmp}" "${TEXTFILE_METRIC}"
  chmod 644 "${TEXTFILE_METRIC}"
}

on_error() {
  local exit_code=$?
  local line_no="${BASH_LINENO[0]}"
  log "ERROR: Backup failed at line ${line_no} (exit ${exit_code})"
  local prev_ts prev_failures duration
  prev_ts=$(grep "backup_last_success_timestamp{job=\"${JOB}\"}" "${TEXTFILE_METRIC}" 2>/dev/null | awk '{print $NF}' || echo 0)
  prev_failures=$(grep "backup_failures_total{job=\"${JOB}\"}" "${TEXTFILE_METRIC}" 2>/dev/null | awk '{print $NF}' || echo 0)
  duration=$(( $(date +%s) - START_TIME ))
  write_metrics 0 "${prev_ts}" 0 "${duration}" "$(( prev_failures + 1 ))"
  exit "${exit_code}"
}
trap on_error ERR

log "=== varys backup starting ==="

if [[ ! -f "${PASSPHRASE_FILE}" ]]; then
  log "ERROR: Passphrase file not found at ${PASSPHRASE_FILE}"
  log "Run: echo 'your-passphrase' | sudo tee ${PASSPHRASE_FILE} && sudo chmod 600 ${PASSPHRASE_FILE}"
  exit 1
fi

if ! command -v gpg >/dev/null 2>&1; then
  log "ERROR: gpg not installed. Run: sudo apt install -y gpg"
  exit 1
fi

log "Mounting NFS share ${NFS_SERVER}:${NFS_SHARE} -> ${MOUNT_POINT}"
mkdir -p "${MOUNT_POINT}"
if mountpoint -q "${MOUNT_POINT}"; then
  log "NFS share already mounted - proceeding."
else
  mount -t nfs "${NFS_SERVER}:${NFS_SHARE}" "${MOUNT_POINT}" -o rw,noatime,vers=4
fi

mkdir -p "${BACKUP_DIR}"
log "Creating encrypted archive: ${ARCHIVE_NAME}"

tar --create \
    --gzip \
    --file=- \
    --ignore-failed-read \
    -C "${HOME}" \
      .kube/config \
      .config/sops/age/keys.txt \
      .ssh/id_ed25519 \
      .ssh/id_ed25519.pub \
      .ssh/config \
      .ssh/known_hosts \
    2>>"${LOG_FILE}" \
| gpg \
    --batch \
    --symmetric \
    --cipher-algo AES256 \
    --compress-algo none \
    --passphrase-file "${PASSPHRASE_FILE}" \
    --output "${BACKUP_DIR}/${ARCHIVE_NAME}"

ARCHIVE_BYTES=$(stat -c %s "${BACKUP_DIR}/${ARCHIVE_NAME}")
log "Archive written: ${BACKUP_DIR}/${ARCHIVE_NAME} ($(du -sh "${BACKUP_DIR}/${ARCHIVE_NAME}" | cut -f1))"

DELETED=$(find "${BACKUP_DIR}" -name "varys_backup_*.tar.gz.gpg" -mtime +${RETENTION_DAYS} -print -delete 2>>"${LOG_FILE}" | wc -l)
if [[ "${DELETED}" -gt 0 ]]; then
  log "Pruned ${DELETED} archive(s) older than ${RETENTION_DAYS} days"
fi

umount "${MOUNT_POINT}"
log "NFS share unmounted."

SUCCESS_TS=$(date +%s)
DURATION=$(( SUCCESS_TS - START_TIME ))
PREV_FAILURES=$(grep "backup_failures_total{job=\"${JOB}\"}" "${TEXTFILE_METRIC}" 2>/dev/null | awk '{print $NF}' || echo 0)
write_metrics 1 "${SUCCESS_TS}" "${ARCHIVE_BYTES}" "${DURATION}" "${PREV_FAILURES}"
log "Prometheus metrics written to ${TEXTFILE_METRIC}"

log "=== varys backup complete ==="
