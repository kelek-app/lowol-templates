# __APP__

This folder runs __APP__ on this server with Docker Compose. It was set up by
Lowol, but nothing here needs Lowol: you can manage it entirely by hand.

| Path | What it is |
| --- | --- |
| `/srv/__APP__/compose.yml` | The app's containers: `web`, `worker`, `scheduler` |
| `/srv/__APP__/.env` | Settings and secrets for all three |
| `/srv/__APP__-mysql/` | MySQL and its nightly backups (see its README) |
| `/srv/__APP__-redis/` | Redis for sessions, cache and queues |
| `/srv/proxy/sites/__APP__.caddy` | Which domain points at this app |

All commands below are run from `/srv/__APP__`.

## Everyday tasks

```sh
docker compose ps                    # what is running
docker compose logs -f web           # follow the web logs (also: worker, scheduler)
docker compose restart               # restart all three
docker compose exec web php artisan tinker
```

## Change a setting

Edit `.env`, then apply it:

```sh
docker compose up -d
```

## Deploy a new version by hand

1. Build the image from your repo, on this server or anywhere with Docker:

   ```sh
   git clone <your repo> /tmp/__APP__ && cd /tmp/__APP__
   git checkout <commit>
   docker build -t __APP__:<commit> .
   ```

   Built elsewhere? Copy it over:
   `docker save __APP__:<commit> | ssh <server> docker load`

2. Run database migrations with the new image:

   ```sh
   cd /srv/__APP__
   APP_TAG=<commit> docker compose run --rm --no-deps web php artisan migrate --force
   ```

3. Switch to it: set `APP_TAG=<commit>` in `.env`, then `docker compose up -d`.

4. Roll back: put the previous tag back in `.env` and run `docker compose up -d`.
   List the tags on this server with `docker image ls __APP__`.

## Remove old images

```sh
docker image ls __APP__
docker image rm __APP__:<old tag>
```
