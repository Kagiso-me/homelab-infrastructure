#!/usr/bin/env bash
# =============================================================================
# backup_docker.sh — Docker appdata backup
#
# Backs up /srv/docker/appdata to NFS-mounted TrueNAS destination.
# Writes Prometheus textfile metrics on completion.
#
# Usage: sudo bash backup_docker.sh
# Cron:  0 2 * * * root /srv/docker/scripts/backup_docker.sh
# =============================================================================

set -euo pipefail

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------
BACKUP_SOURCE="/srv/docker/appdata"
BACKUP_DEST="/mnt/archive/backups/docker"
NFS_MOUNTPOINT="/mnt/archive/backups"
LOG_FILE="/var/log/docker-backup.log"
RETENTION_DAYS=7
TEXTFILE_DIR="/var/lib/node_exporter/textfile_collector"
TEXTFILE_METRIC="${TEXTFILE_DIR}/docker_backup.prom"
DATE=$(date +%Y-%m-%d_%H%M%S)
ARCHIVE="${BACKUP_DEST}/docker_appdata_${DATE}.tar.gz"

# -----------------------------------------------------------------------------
# Logging helper
# -----------------------------------------------------------------------------
log() {
  local level="$1"
  shift
  local msg="$*"
  local ts
  ts=$(date '+%Y-%m-%d %H:%M:%S')
  echo "${ts} [${level}] ${msg}" | tee -a "${LOG_FILE}"
}

# -----------------------------------------------------------------------------
# Error handler — write failure metric and exit
# -----------------------------------------------------------------------------
on_error() {
  local exit_code=$?
  local line_no="${BASH_LINENO[0]}"
  log "ERROR" "Backup failed at line ${line_no} with exit code ${exit_code}."
  # Write failure indicator — keep last success timestamp unchanged, size 0
  if [[ -f "${TEXTFILE_METRIC}" ]]; then
    local last_ts
    last_ts=$(grep 'docker_backup_last_success_timestamp' "${TEXTFILE_METRIC}" | awk '{print $2}' || echo 0)
    write_metrics "${last_ts}" "0"
  fi
  exit "${exit_code}"
}
trap on_error ERR

# -----------------------------------------------------------------------------
# Write Prometheus textfile metrics
# -----------------------------------------------------------------------------
write_metrics() {
  local ts="$1"
  local size_bytes="$2"
  mkdir -p "${TEXTFILE_DIR}"
  # Write atomically via temp file
  local tmp
  tmp=$(mktemp "${TEXTFILE_METRIC}.XXXXXX")
  cat > "${tmp}" <<EOF
# HELP docker_backup_last_success_timestamp Unix timestamp of the last successful Docker appdata backup.
# TYPE docker_backup_last_success_timestamp gauge
docker_backup_last_success_timestamp ${ts}
# HELP docker_backup_size_bytes Size in bytes of the most recent Docker appdata backup archive.
# TYPE docker_backup_size_bytes gauge
docker_backup_size_bytes ${size_bytes}
EOF
  mv "${tmp}" "${TEXTFILE_METRIC}"
  chmod 644 "${TEXTFILE_METRIC}"
}

# -----------------------------------------------------------------------------
# Verify NFS mount
# -----------------------------------------------------------------------------
log "INFO" "Verifying NFS mount at ${NFS_MOUNTPOINT} ..."
if ! mountpoint -q "${NFS_MOUNTPOINT}"; then
  log "ERROR" "${NFS_MOUNTPOINT} is not mounted. Aborting backup."
  exit 2
fi
log "INFO" "NFS mount verified."

# -----------------------------------------------------------------------------
# Ensure destination directory exists
# -----------------------------------------------------------------------------
mkdir -p "${BACKUP_DEST}"

# -----------------------------------------------------------------------------
# Run backup
# -----------------------------------------------------------------------------
log "INFO" "Starting Docker appdata backup."
log "INFO" "Source      : ${BACKUP_SOURCE}"
log "INFO" "Destination : ${ARCHIVE}"

tar \
  --create \
  --gzip \
  --file="${ARCHIVE}" \
  --one-file-system \
  --exclude="${BACKUP_SOURCE}/*/logs" \
  --exclude="${BACKUP_SOURCE}/*/cache" \
  --exclude="${BACKUP_SOURCE}/*/Cache" \
  --exclude="${BACKUP_SOURCE}/*/transcodes" \
  "${BACKUP_SOURCE}"

# -----------------------------------------------------------------------------
# Report backup size
# -----------------------------------------------------------------------------
BACKUP_SIZE_BYTES=$(stat --format="%s" "${ARCHIVE}")
BACKUP_SIZE_HUMAN=$(du -sh "${ARCHIVE}" | cut -f1)
log "INFO" "Backup completed successfully."
log "INFO" "Archive size: ${BACKUP_SIZE_HUMAN} (${BACKUP_SIZE_BYTES} bytes)"
log "INFO" "Archive path: ${ARCHIVE}"

# -----------------------------------------------------------------------------
# Enforce retention — delete archives older than RETENTION_DAYS
# -----------------------------------------------------------------------------
log "INFO" "Enforcing ${RETENTION_DAYS}-day retention policy ..."
DELETED_COUNT=0
while IFS= read -r old_archive; do
  log "INFO" "Deleting old archive: ${old_archive}"
  rm -f "${old_archive}"
  (( DELETED_COUNT++ )) || true
done < <(find "${BACKUP_DEST}" -maxdepth 1 -name "docker_appdata_*.tar.gz" -mtime "+${RETENTION_DAYS}" -type f)
log "INFO" "Retention sweep complete. Deleted ${DELETED_COUNT} archive(s)."

# -----------------------------------------------------------------------------
# Write Prometheus metrics
# -----------------------------------------------------------------------------
SUCCESS_TS=$(date +%s)
write_metrics "${SUCCESS_TS}" "${BACKUP_SIZE_BYTES}"
log "INFO" "Prometheus metrics written to ${TEXTFILE_METRIC}"

log "INFO" "Backup job finished."
