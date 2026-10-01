#!/usr/bin/env bash
# Restores a dump into the database. This REPLACES the current data, so a
# fresh backup is taken first.
#
#   docker compose exec backup ls -lh /backups                     # list dumps
#   docker compose exec backup bash /scripts/restore.sh <file name>
set -euo pipefail

file="${1:?usage: restore.sh <dump file name in /backups>}"
[[ "$file" == /* ]] || file="/backups/$file"
if [[ ! -f "$file" ]]; then
    echo "No such dump: $file" >&2
    echo "Dumps on this server:" >&2
    ls -1 /backups >&2
    exit 1
fi

echo "Taking a safety backup of the current data first..."
bash /scripts/backup.sh now

CNF="$(mktemp)"
trap 'rm -f "$CNF"' EXIT
printf '[client]\nuser=root\npassword="%s"\nhost=%s\n' "$MYSQL_ROOT_PASSWORD" "${MYSQL_HOST:-mysql}" > "$CNF"

echo "Restoring $(basename "$file") into ${MYSQL_DATABASE}..."
gunzip -c "$file" | mysql --defaults-extra-file="$CNF" "$MYSQL_DATABASE"
echo "Done."
