#!/usr/bin/env bash
# Dumps the database every night at BACKUP_HOUR and keeps BACKUP_KEEP_DAYS
# days of dumps in /backups (the "backups" volume).
#
# Back up right now:
#   docker compose exec backup bash /scripts/backup.sh now
set -euo pipefail

HOUR="${BACKUP_HOUR:-3}"
KEEP_DAYS="${BACKUP_KEEP_DAYS:-14}"
HOST="${MYSQL_HOST:-mysql}"
DIR=/backups

log() { echo "[backup $(date -u +%Y-%m-%dT%H:%M:%SZ)] $*"; }

# Credentials go in a temporary options file, not on the command line.
CNF="$(mktemp)"
trap 'rm -f "$CNF"' EXIT
printf '[client]\nuser=root\npassword="%s"\nhost=%s\n' "$MYSQL_ROOT_PASSWORD" "$HOST" > "$CNF"

dump() {
    local file tmp
    file="$DIR/${MYSQL_DATABASE}-$(date -u +%Y%m%d-%H%M%S).sql.gz"
    tmp="$file.tmp"
    log "dumping ${MYSQL_DATABASE}"
    if ! mysqldump --defaults-extra-file="$CNF" \
            --single-transaction --quick --routines --triggers --events --no-tablespaces \
            "$MYSQL_DATABASE" | gzip -6 > "$tmp"; then
        rm -f "$tmp"
        log "FAILED: dump of ${MYSQL_DATABASE} did not complete"
        return 1
    fi
    mv "$tmp" "$file"
    log "wrote $(basename "$file") ($(du -h "$file" | cut -f1))"
    # Remove dumps older than KEEP_DAYS days.
    local cutoff old
    cutoff=$(( $(date +%s) - KEEP_DAYS * 86400 ))
    for old in "$DIR"/*.sql.gz; do
        [[ -e "$old" ]] || continue
        if (( $(stat -c %Y "$old") < cutoff )); then
            rm -f "$old"
            log "removed $(basename "$old") (older than ${KEEP_DAYS} days)"
        fi
    done
}

seconds_until_next_run() {
    local now next at
    at="$(printf '%02d:00' "$HOUR")"
    now="$(date +%s)"
    next="$(date -d "today $at" +%s)"
    if (( next <= now )); then
        next="$(date -d "tomorrow $at" +%s)"
    fi
    echo $(( next - now ))
}

if [[ "${1:-}" == "now" ]]; then
    dump
    exit
fi

log "nightly backups at $(printf '%02d:00' "$HOUR"), keeping ${KEEP_DAYS} days"
while true; do
    sleep "$(seconds_until_next_run)"
    dump || true
done
