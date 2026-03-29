#!/usr/bin/env bash
# =============================================================================
# restore_docker.sh - Docker appdata restore
#
# Restores /srv/docker/appdata from an archive created by backup_docker.sh.
#
# Modes:
#   1. Production restore (default target root "/")
#      - stops running containers
#      - restores into /srv/docker/appdata
#
#   2. Drill restore (--target-root <path>)
#      - does NOT stop containers
#      - restores into <path>/srv/docker/appdata
#      - safe for rehearsals and validation drills
#
# Usage:
#   sudo bash restore_docker.sh <backup_archive_path>
#   sudo bash restore_docker.sh --target-root /srv/docker/restore-drill/2026-03-29 <backup_archive_path>
# =============================================================================

set -euo pipefail

readonly E_USAGE=1
readonly E_NOT_FOUND=2
readonly E_NOT_ARCHIVE=3
readonly E_ABORTED=4
readonly E_DOCKER=5
readonly E_EXTRACT=6
readonly E_TARGET=7

log() {
  local level="$1"
  shift
  local ts
  ts=$(date '+%Y-%m-%d %H:%M:%S')
  echo "${ts} [${level}] $*"
}

usage() {
  echo ""
  echo "  Usage:"
  echo "    $(basename "$0") [--target-root <path>] <backup_archive_path>"
  echo ""
  echo "  Examples:"
  echo "    sudo bash $(basename "$0") /mnt/archive/backups/docker/docker_appdata_2026-03-14_020000.tar.gz"
  echo "    sudo bash $(basename "$0") --target-root /srv/docker/restore-drill/2026-03-29 \\"
  echo "      /mnt/archive/backups/docker/docker_appdata_2026-03-14_020000.tar.gz"
  echo ""
}

TARGET_ROOT="/"
ARCHIVE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --target-root)
      shift
      if [[ $# -eq 0 ]]; then
        usage
        exit "${E_USAGE}"
      fi
      TARGET_ROOT="$1"
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    -*)
      log "ERROR" "Unknown option: $1"
      usage
      exit "${E_USAGE}"
      ;;
    *)
      if [[ -n "${ARCHIVE}" ]]; then
        log "ERROR" "Only one archive path may be supplied."
        usage
        exit "${E_USAGE}"
      fi
      ARCHIVE="$1"
      ;;
  esac
  shift
done

if [[ -z "${ARCHIVE}" ]]; then
  usage
  exit "${E_USAGE}"
fi

DRILL_MODE=false
if [[ "${TARGET_ROOT}" != "/" ]]; then
  DRILL_MODE=true
fi

if [[ ! -f "${ARCHIVE}" ]]; then
  log "ERROR" "Archive not found: ${ARCHIVE}"
  exit "${E_NOT_FOUND}"
fi

if [[ "${ARCHIVE}" != *.tar.gz && "${ARCHIVE}" != *.tgz ]]; then
  log "ERROR" "File does not appear to be a .tar.gz archive: ${ARCHIVE}"
  exit "${E_NOT_ARCHIVE}"
fi

log "INFO" "Verifying archive integrity ..."
if ! tar --test-label --file="${ARCHIVE}" &>/dev/null && ! tar -tzf "${ARCHIVE}" &>/dev/null; then
  log "ERROR" "Archive integrity check failed. The file may be corrupt."
  exit "${E_NOT_ARCHIVE}"
fi
log "INFO" "Archive integrity OK."

if [[ "${DRILL_MODE}" == true ]]; then
  mkdir -p "${TARGET_ROOT}" || {
    log "ERROR" "Unable to create target root: ${TARGET_ROOT}"
    exit "${E_TARGET}"
  }
fi

ARCHIVE_SIZE_BYTES=$(stat --format="%s" "${ARCHIVE}")
ARCHIVE_SIZE_HUMAN=$(du -sh "${ARCHIVE}" | cut -f1)
ARCHIVE_DATE=$(stat --format="%y" "${ARCHIVE}" | cut -d'.' -f1)
ARCHIVE_NAME=$(basename "${ARCHIVE}")
RESTORED_APPDATA_PATH="${TARGET_ROOT%/}/srv/docker/appdata"
if [[ "${TARGET_ROOT}" == "/" ]]; then
  RESTORED_APPDATA_PATH="/srv/docker/appdata"
fi

echo ""
echo "============================================================"
echo "  Docker Appdata Restore"
echo "============================================================"
echo "  Archive      : ${ARCHIVE_NAME}"
echo "  Source path  : ${ARCHIVE}"
echo "  Size         : ${ARCHIVE_SIZE_HUMAN} (${ARCHIVE_SIZE_BYTES} bytes)"
echo "  Modified     : ${ARCHIVE_DATE}"
if [[ "${DRILL_MODE}" == true ]]; then
  echo "  Mode         : DRILL"
  echo "  Target root  : ${TARGET_ROOT}"
  echo "  Extracts to  : ${RESTORED_APPDATA_PATH}"
else
  echo "  Mode         : PRODUCTION"
  echo "  Extracts to  : /srv/docker/appdata"
fi
echo "============================================================"
echo ""

log "INFO" "Top-level directories in archive:"
tar -tzf "${ARCHIVE}" | awk -F'/' 'NF>=3{print $1"/"$2"/"$3}' | sort -u | head -40
echo ""

RUNNING_CONTAINERS=""
RUNNING_NAMES=""
if [[ "${DRILL_MODE}" == false ]]; then
  log "INFO" "Identifying running Docker containers ..."
  RUNNING_CONTAINERS=$(docker ps -q || true)
  if [[ -z "${RUNNING_CONTAINERS}" ]]; then
    log "INFO" "No running containers found."
  else
    RUNNING_NAMES=$(docker ps --format '{{.Names}}' | tr '\n' ' ')
    log "INFO" "Running containers: ${RUNNING_NAMES}"
  fi
fi

echo ""
if [[ "${DRILL_MODE}" == true ]]; then
  echo "  This is a DRILL restore."
  echo "    1. Running containers will NOT be stopped."
  echo "    2. Archive contents will be extracted under ${TARGET_ROOT}."
  echo "    3. Production appdata will NOT be overwritten."
else
  echo "  WARNING: This will:"
  echo "    1. Stop ALL running Docker containers."
  echo "    2. Overwrite /srv/docker/appdata with the contents of the archive."
fi
echo ""
read -r -p "  Proceed? [y/N] " CONFIRM
echo ""

case "${CONFIRM}" in
  [yY][eE][sS]|[yY])
    log "INFO" "Confirmed. Proceeding."
    ;;
  *)
    log "INFO" "Restore aborted by user."
    exit "${E_ABORTED}"
    ;;
esac

if [[ "${DRILL_MODE}" == false && -n "${RUNNING_CONTAINERS}" ]]; then
  log "INFO" "Stopping all running containers (graceful, 30s timeout) ..."
  if ! docker stop --time=30 ${RUNNING_CONTAINERS}; then
    log "ERROR" "Failed to stop one or more containers. Aborting to avoid data corruption."
    exit "${E_DOCKER}"
  fi
  log "INFO" "All containers stopped."
fi

log "INFO" "Extracting archive ..."
log "INFO" "  Source : ${ARCHIVE}"
log "INFO" "  Target : ${TARGET_ROOT}"

if ! tar -xzf "${ARCHIVE}" -C "${TARGET_ROOT}"; then
  log "ERROR" "Extraction failed."
  exit "${E_EXTRACT}"
fi

log "INFO" "Extraction complete."

if [[ -d "${RESTORED_APPDATA_PATH}" ]]; then
  log "INFO" "Restored appdata path detected: ${RESTORED_APPDATA_PATH}"
  if [[ "${DRILL_MODE}" == false ]]; then
    log "INFO" "Correcting ownership on ${RESTORED_APPDATA_PATH} (PUID=1000, PGID=1000) ..."
    chown -R 1000:1000 "${RESTORED_APPDATA_PATH}" || log "WARN" "chown encountered errors - review manually."
  fi
else
  log "WARN" "Expected restore path not found: ${RESTORED_APPDATA_PATH}"
fi

echo ""
echo "============================================================"
echo "  Restore Complete - Next Steps"
echo "============================================================"
echo ""

if [[ "${DRILL_MODE}" == true ]]; then
  echo "  Drill validation suggestions:"
  echo ""
  echo "  1. Check the extracted directory exists:"
  echo "       ls -lah ${RESTORED_APPDATA_PATH}"
  echo ""
  echo "  2. Confirm key app directories are present:"
  echo "       find ${RESTORED_APPDATA_PATH} -maxdepth 2 -type d | sort | head -40"
  echo ""
  echo "  3. Record the archive tested, date, and findings in the game-day log."
  echo ""
  echo "  4. Remove the drill directory when finished:"
  echo "       rm -rf ${TARGET_ROOT}"
else
  echo "  Start stacks in the following order:"
  echo ""
  echo "  1. Verify NFS mounts are active:"
  echo "       mountpoint -q /mnt/media && echo OK || echo MISSING"
  echo "       mountpoint -q /mnt/downloads && echo OK || echo MISSING"
  echo "       mountpoint -q /mnt/archive/backups && echo OK || echo MISSING"
  echo ""
  echo "  2. Start the media stack:"
  echo "       cd /srv/docker/stacks"
  echo "       docker compose -f media-stack.yml up -d"
  echo ""
  echo "  3. Start the proxy stack:"
  echo "       docker compose -f proxy-stack.yml up -d"
  echo ""
  echo "  4. Start the monitoring stack:"
  echo "       docker compose -f monitoring-stack.yml up -d"
  echo ""
  echo "  5. Verify all containers are healthy:"
  echo "       docker ps --format 'table {{.Names}}\t{{.Status}}'"
fi

echo ""
echo "============================================================"
echo ""
log "INFO" "Restore job finished successfully."
