#!/bin/sh
# Copies new dumps from /backups to object storage every hour and removes
# copies older than BACKUP_KEEP_DAYS days.
#
# Bring a dump back from object storage before a restore:
#   docker compose exec upload sh -c 'rclone copy "spaces:$BACKUP_BUCKET/$BACKUP_PREFIX/<file>" /backups/'
set -eu

KEEP_DAYS="${BACKUP_KEEP_DAYS:-14}"

log() { echo "[upload $(date -u +%Y-%m-%dT%H:%M:%SZ)] $*"; }

if [ -z "${BACKUP_BUCKET:-}" ]; then
    log "BACKUP_BUCKET is empty: dumps stay on this server only."
    while true; do sleep 86400; done
fi

REMOTE="spaces:${BACKUP_BUCKET}/${BACKUP_PREFIX:-backups}"
log "copying dumps to ${REMOTE} every hour, keeping ${KEEP_DAYS} days"

while true; do
    rclone copy /backups "$REMOTE" --include '*.sql.gz' --quiet \
        || log "FAILED: copy to ${REMOTE}"
    rclone delete "$REMOTE" --include '*.sql.gz' --min-age "${KEEP_DAYS}d" --quiet \
        || log "FAILED: removing old copies from ${REMOTE}"
    sleep 3600
done
