#!/usr/bin/env bash
# =============================================================================
# restore_docker.sh — Docker appdata restore
#
# Restores /srv/docker/appdata from a backup archive created by backup_docker.sh.
# Stops all running containers before extracting and prints next steps.
#
# Usage: sudo bash restore_docker.sh <backup_archive_path>
# Example:
#   sudo bash restore_docker.sh \
#     /mnt/tank/k8s-backups/docker/docker_appdata_2026-03-14_020000.tar.gz
# =============================================================================

set -euo pipefail

# -----------------------------------------------------------------------------
# Exit codes
# -----------------------------------------------------------------------------
readonly E_USAGE=1
readonly E_NOT_FOUND=2
readonly E_NOT_ARCHIVE=3
readonly E_ABORTED=4
readonly E_DOCKER=5
readonly E_EXTRACT=6

# -----------------------------------------------------------------------------
# Logging helper
# -----------------------------------------------------------------------------
log() {
  local level="$1"
  shift
  local ts
  ts=$(date '+%Y-%m-%d %H:%M:%S')
  echo "${ts} [${level}] $*"
}

# -----------------------------------------------------------------------------
# Usage guard
# -----------------------------------------------------------------------------
if [[ $# -lt 1 ]]; then
  echo ""
  echo "  Usage: $(basename "$0") <backup_archive_path>"
  echo ""
  echo "  Example:"
  echo "    sudo bash $(basename "$0") \\"
  echo "      /mnt/tank/k8s-backups/docker/docker_appdata_2026-03-14_020000.tar.gz"
  echo ""
  exit "${E_USAGE}"
fi

ARCHIVE="$1"

# -----------------------------------------------------------------------------
# Validate archive exists and looks like a tar.gz
# -----------------------------------------------------------------------------
if [[ ! -f "${ARCHIVE}" ]]; then
  log "ERROR" "Archive not found: ${ARCHIVE}"
  exit "${E_NOT_FOUND}"
fi

if [[ "${ARCHIVE}" != *.tar.gz && "${ARCHIVE}" != *.tgz ]]; then
  log "ERROR" "File does not appear to be a .tar.gz archive: ${ARCHIVE}"
  exit "${E_NOT_ARCHIVE}"
fi

# Verify the archive is not corrupt before doing anything destructive
log "INFO" "Verifying archive integrity ..."
if ! tar --test-label --file="${ARCHIVE}" &>/dev/null && ! tar -tzf "${ARCHIVE}" &>/dev/null; then
  log "ERROR" "Archive integrity check failed. The file may be corrupt."
  exit "${E_NOT_ARCHIVE}"
fi
log "INFO" "Archive integrity OK."

# -----------------------------------------------------------------------------
# Print archive info
# -----------------------------------------------------------------------------
ARCHIVE_SIZE_BYTES=$(stat --format="%s" "${ARCHIVE}")
ARCHIVE_SIZE_HUMAN=$(du -sh "${ARCHIVE}" | cut -f1)
ARCHIVE_DATE=$(stat --format="%y" "${ARCHIVE}" | cut -d'.' -f1)
ARCHIVE_NAME=$(basename "${ARCHIVE}")

echo ""
echo "============================================================"
echo "  Docker Appdata Restore"
echo "============================================================"
echo "  Archive : ${ARCHIVE_NAME}"
echo "  Path    : ${ARCHIVE}"
echo "  Size    : ${ARCHIVE_SIZE_HUMAN} (${ARCHIVE_SIZE_BYTES} bytes)"
echo "  Modified: ${ARCHIVE_DATE}"
echo "============================================================"
echo ""

# -----------------------------------------------------------------------------
# List top-level contents for review
# -----------------------------------------------------------------------------
log "INFO" "Top-level directories in archive:"
tar -tzf "${ARCHIVE}" | awk -F'/' 'NF>=3{print $1"/"$2"/"$3}' | sort -u | head -40
echo ""

# -----------------------------------------------------------------------------
# Stop all running Docker containers
# -----------------------------------------------------------------------------
log "INFO" "Identifying running Docker containers ..."
RUNNING_CONTAINERS=$(docker ps -q)

if [[ -z "${RUNNING_CONTAINERS}" ]]; then
  log "INFO" "No running containers found."
else
  RUNNING_NAMES=$(docker ps --format '{{.Names}}' | tr '\n' ' ')
  log "INFO" "Running containers: ${RUNNING_NAMES}"
fi

# -----------------------------------------------------------------------------
# Confirmation prompt
# -----------------------------------------------------------------------------
echo ""
echo "  WARNING: This will:"
echo "    1. Stop ALL running Docker containers."
echo "    2. Overwrite /srv/docker/appdata with the contents of the archive."
echo ""
echo "  This operation CANNOT be undone automatically."
echo "  Ensure you have verified the archive listed above is the correct backup."
echo ""
read -r -p "  Proceed with restore? [y/N] " CONFIRM
echo ""

case "${CONFIRM}" in
  [yY][eE][sS]|[yY])
    log "INFO" "Confirmed. Proceeding with restore."
    ;;
  *)
    log "INFO" "Restore aborted by user."
    exit "${E_ABORTED}"
    ;;
esac

# -----------------------------------------------------------------------------
# Stop containers
# -----------------------------------------------------------------------------
if [[ -n "${RUNNING_CONTAINERS}" ]]; then
  log "INFO" "Stopping all running containers (graceful, 30s timeout) ..."
  if ! docker stop --time=30 ${RUNNING_CONTAINERS}; then
    log "ERROR" "Failed to stop one or more containers. Aborting to avoid data corruption."
    exit "${E_DOCKER}"
  fi
  log "INFO" "All containers stopped."
else
  log "INFO" "No containers to stop."
fi

# -----------------------------------------------------------------------------
# Extract archive
# -----------------------------------------------------------------------------
log "INFO" "Extracting archive to / ..."
log "INFO" "  Source : ${ARCHIVE}"
log "INFO" "  Target : /  (restores /srv/docker/appdata/...)"

if ! tar -xzf "${ARCHIVE}" -C /; then
  log "ERROR" "Extraction failed. Your appdata directory may be in a partial state."
  log "ERROR" "DO NOT start containers until you verify the restore."
  exit "${E_EXTRACT}"
fi

log "INFO" "Extraction complete."

# -----------------------------------------------------------------------------
# Fix ownership (all appdata should be owned by kagiso, PUID/PGID 1000)
# -----------------------------------------------------------------------------
log "INFO" "Correcting ownership on /srv/docker/appdata (PUID=1000, PGID=1000) ..."
chown -R 1000:1000 /srv/docker/appdata || log "WARN" "chown encountered errors — review manually."

# -----------------------------------------------------------------------------
# Next steps
# -----------------------------------------------------------------------------
echo ""
echo "============================================================"
echo "  Restore Complete — Next Steps"
echo "============================================================"
echo ""
echo "  Start stacks in the following order:"
echo ""
echo "  1. Verify NFS mounts are active:"
echo "       mountpoint -q /mnt/media    && echo OK || echo MISSING"
echo "       mountpoint -q /mnt/downloads && echo OK || echo MISSING"
echo "       mountpoint -q /mnt/tank      && echo OK || echo MISSING"
echo ""
echo "  2. Create the Docker networks if they do not exist:"
echo "       docker network create media-net"
echo "       docker network create monitoring-net"
echo ""
echo "  3. Start the proxy stack first (provides reverse proxy):"
echo "       cd /srv/docker/compose"
echo "       docker compose -f proxy-stack.yml up -d"
echo ""
echo "  4. Start the monitoring stack:"
echo "       docker compose -f monitoring-stack.yml up -d"
echo ""
echo "  5. Start the media stack:"
echo "       docker compose -f media-stack.yml up -d"
echo ""
echo "  6. Verify all containers are healthy:"
echo "       docker ps --format 'table {{.Names}}\t{{.Status}}'"
echo ""
echo "  7. Check logs for any errors:"
echo "       docker compose -f media-stack.yml logs --tail=50"
echo "       docker compose -f monitoring-stack.yml logs --tail=50"
echo ""
echo "============================================================"
echo ""
log "INFO" "Restore job finished successfully."
