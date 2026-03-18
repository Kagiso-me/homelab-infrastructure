#!/usr/bin/env bash
# backup_rpi.sh — Raspberry Pi key material backup to TrueNAS NFS
# Author: Kagiso Tjeane
# Schedule: daily at 01:00 via cron
# See: raspberry-pi/docs/03_backup.md
#
# What is backed up:
#   ~/.kube/config              — kubeconfig for k3s cluster
#   ~/.config/sops/age/keys.txt — age private key (CRITICAL)
#   ~/.ssh/id_ed25519           — SSH private key
#   ~/.ssh/id_ed25519.pub       — SSH public key
#   ~/.ssh/config               — SSH host aliases
#   ~/.ssh/known_hosts          — SSH fingerprints
#
# The archive is GPG-encrypted (AES-256) before being written to TrueNAS.
# This is mandatory — the backup contains the age private key.
#
# Setup (one-time):
#   echo "your-strong-passphrase" | sudo tee /root/.rpi_backup_passphrase
#   sudo chmod 600 /root/.rpi_backup_passphrase
#   sudo mkdir -p /mnt/backup_rpi

set -euo pipefail

# ── Configuration ────────────────────────────────────────────────────────────
NFS_SERVER="10.0.10.80"
NFS_SHARE="/mnt/archive/backups/rpi"
MOUNT_POINT="/mnt/backup_rpi"
RETENTION_DAYS=30
TIMESTAMP=$(date +"%Y-%m-%d_%H%M%S")
ARCHIVE_NAME="rpi_backup_${TIMESTAMP}.tar.gz.gpg"
LOG_FILE="/var/log/rpi-backup.log"
# Passphrase file — readable only by root
# Must be created during initial setup (see above)
PASSPHRASE_FILE="/root/.rpi_backup_passphrase"

# ── Logging helper ───────────────────────────────────────────────────────────
log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "${LOG_FILE}"
}

log "=== RPi backup starting ==="

# ── Pre-flight checks ────────────────────────────────────────────────────────
if [[ ! -f "${PASSPHRASE_FILE}" ]]; then
  log "ERROR: Passphrase file not found at ${PASSPHRASE_FILE}"
  log "Run: echo 'your-passphrase' | sudo tee ${PASSPHRASE_FILE} && sudo chmod 600 ${PASSPHRASE_FILE}"
  exit 1
fi

if ! command -v gpg &>/dev/null; then
  log "ERROR: gpg not installed. Run: sudo apt install -y gpg"
  exit 1
fi

# ── Mount NFS share ──────────────────────────────────────────────────────────
log "Mounting NFS share ${NFS_SERVER}:${NFS_SHARE} → ${MOUNT_POINT}"
mkdir -p "${MOUNT_POINT}"

if mountpoint -q "${MOUNT_POINT}"; then
  log "NFS share already mounted — proceeding."
else
  mount -t nfs "${NFS_SERVER}:${NFS_SHARE}" "${MOUNT_POINT}" \
    -o rw,noatime,vers=4
fi

# ── Create encrypted archive ─────────────────────────────────────────────────
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
    --output "${MOUNT_POINT}/${ARCHIVE_NAME}"

ARCHIVE_SIZE=$(du -sh "${MOUNT_POINT}/${ARCHIVE_NAME}" | cut -f1)
# Capture byte size BEFORE unmounting (used for Prometheus metric below)
ARCHIVE_BYTES=$(stat -c %s "${MOUNT_POINT}/${ARCHIVE_NAME}")
log "Archive written: ${MOUNT_POINT}/${ARCHIVE_NAME} (${ARCHIVE_SIZE})"

# ── Enforce retention ────────────────────────────────────────────────────────
DELETED=$(find "${MOUNT_POINT}" -name "rpi_backup_*.tar.gz.gpg" \
  -mtime +${RETENTION_DAYS} -print -delete 2>>"${LOG_FILE}" | wc -l)

if [ "${DELETED}" -gt 0 ]; then
  log "Pruned ${DELETED} archive(s) older than ${RETENTION_DAYS} days"
fi

# ── Unmount NFS share ────────────────────────────────────────────────────────
umount "${MOUNT_POINT}"
log "NFS share unmounted."

# ── Prometheus metrics ───────────────────────────────────────────────────────
METRICS_DIR="/var/lib/node_exporter/textfile_collector"
if [ -d "${METRICS_DIR}" ]; then
  MTIME=$(date +%s)
  SIZE="${ARCHIVE_BYTES}"
  TMPFILE="${METRICS_DIR}/.rpi_backup.prom.tmp"
  cat > "${TMPFILE}" <<EOF
# HELP rpi_backup_last_success_timestamp Unix timestamp of the last successful RPi backup
# TYPE rpi_backup_last_success_timestamp gauge
rpi_backup_last_success_timestamp ${MTIME}
# HELP rpi_backup_size_bytes Size of the most recent RPi backup archive in bytes
# TYPE rpi_backup_size_bytes gauge
rpi_backup_size_bytes ${SIZE}
EOF
  mv "${TMPFILE}" "${METRICS_DIR}/rpi_backup.prom"
fi

log "=== RPi backup complete ==="
