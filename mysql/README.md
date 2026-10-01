# __DB__

MySQL for __APP__, with nightly backups. Set up by Lowol; nothing here needs
Lowol. All commands are run from `/srv/__DB__`.

| File | What it is |
| --- | --- |
| `compose.yml` | `mysql`, plus `backup` (nightly dump) and `upload` (copy to object storage) |
| `.env` | Database name and passwords |
| `backup.env` | Backup time, how long to keep dumps, object storage keys |
| `scripts/` | The backup, restore and upload scripts |

Apps reach the database as host `__DB__`, port 3306, on the Docker network `__DB__`.

## Backups

- Every night at `BACKUP_HOUR` a compressed dump is written to the `backups`
  volume and kept for `BACKUP_KEEP_DAYS` days.
- If `BACKUP_BUCKET` is set, dumps are also copied to object storage every
  hour, under `BACKUP_PREFIX/`, and old copies are removed after the same
  number of days.

```sh
docker compose exec backup bash /scripts/backup.sh now     # back up now
docker compose exec backup ls -lh /backups                 # list dumps
docker compose logs backup upload                          # check they ran
```

## Restore

Restoring replaces the current data. The script takes a fresh backup first.

```sh
docker compose exec backup bash /scripts/restore.sh <dump file name>
```

The dump is only in object storage? Bring it back first:

```sh
docker compose exec upload sh -c 'rclone copy "spaces:$BACKUP_BUCKET/$BACKUP_PREFIX/<dump file name>" /backups/'
```

## Stop backups

Remove the `backup` and `upload` services from `compose.yml`, then run
`docker compose up -d --remove-orphans`. Delete the object storage key from
your cloud account if nothing else uses it.
