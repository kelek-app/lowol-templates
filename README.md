# lowol-templates

The files Lowol writes to your server, in the open. Only files the services
need go on a server; this README is where the how-tos live. Everything here is plain
Docker and Docker Compose: if you stop using Lowol, your server keeps running
these files exactly as they are, and you can manage them by hand.

## What's here

| Folder | Goes to | What it is |
| --- | --- | --- |
| `laravel/Dockerfile`, `laravel/.dockerignore`, `laravel/docker/` | your repo | Production image for a Laravel app (FrankenPHP, PHP 8.4) |
| `laravel/server/` | `/srv/<app>/` | Compose file for `web`, `worker` and `scheduler`, plus `.env` |
| `proxy/` | `/srv/proxy/` | Caddy on ports 80/443 with automatic HTTPS, shared by all apps on the server. `trusted-proxies.caddy` lists Cloudflare's addresses, so apps behind Cloudflare's proxy see their visitors' addresses |
| `proxy-site/` | `/srv/proxy/sites/<app>.caddy` | Points a domain at one app |
| `mysql/` | `/srv/<app>-mysql/` | MySQL 8.4 (or 8.0, set in `.env`) with nightly backups to object storage |
| `redis/` | `/srv/<app>-redis/` | Redis 7 for sessions, cache and queues |
| `example/` | — | A minimal Laravel app with these files, for trying Lowol or the setup below |
| `scripts/render.sh` | — | Fills in the `__PLACEHOLDERS__` (what Lowol does when it writes these files) |
| `scripts/try-local.sh` | — | Runs the whole setup on your own machine |

On a server it looks like this:

```
/srv/proxy/                  Caddy; sites/<app>.caddy per app, trusted-proxies.caddy
/srv/myapp/                  compose.yml, .env
/srv/myapp-mysql/            compose.yml, .env, backup.env, scripts/
/srv/myapp-redis/            compose.yml, .env
```

Containers are named after the app (`myapp-web-1`, `myapp-worker-1`), and the
only images on the server are the ones in use, under plain local tags
(`myapp:<commit>`).

## How requests and data flow

```
internet ──443──> proxy (Caddy) ──"myapp-web:8080"──> myapp web
                                                       myapp worker, scheduler
                                    network "myapp-mysql" ──> MySQL ──> nightly dump ──> object storage
                                    network "myapp-redis" ──> Redis
```

- The proxy and the apps share the Docker network `proxy`. Each app's web
  container is reachable there as `<app>-web` on port 8080.
- Each database creates its own network named after it. Apps that use it join
  that network and reach it by the same name (`DB_HOST=myapp-mysql`).
- Nothing is published on the server's public IP except ports 80 and 443.

## Use the Laravel image in your app

1. Copy `laravel/Dockerfile`, `laravel/.dockerignore` and `laravel/docker/` into
   the root of your Laravel repo.
2. Make sure your app:
   - **trusts the proxy**, so it generates `https://` links. Laravel 11+, in
     `bootstrap/app.php`:
     ```php
     ->withMiddleware(function (Middleware $middleware) {
         $middleware->trustProxies(at: '*');
     })
     ```
   - **is stateless**: sessions, cache and queues in Redis, uploads in object
     storage (`composer require league/flysystem-aws-s3-v3`). The `.env` in
     `laravel/server/` already points there.
   - logs to stderr (`LOG_CHANNEL=stderr`, also already set).
3. Build: `docker build -t myapp:local .`

The image listens on `$PORT` (8080 by default) on all interfaces. Before each
process starts, it runs `php artisan optimize` so config is cached from the
real environment variables. Set `SKIP_OPTIMIZE=1` to turn that off.

Using pnpm or Yarn instead of npm? Change the two `npm` lines in the
`assets` stage of the Dockerfile.

## Try it on your machine

Needs Docker with Compose v2 and a Laravel app.

```sh
scripts/try-local.sh up ~/code/my-laravel-app   # opens on http://localhost:8080
scripts/try-local.sh down                       # removes everything again
```

It builds the image, renders the server files into `.try/` (open them: this
is exactly what a server gets), starts the proxy, MySQL, Redis and the app,
and runs migrations. Differences from a real server: plain HTTP on one port,
and uploads stored locally instead of in object storage.

Or try it with the example app: `scripts/try-local.sh up example`.

## Render files yourself

```sh
scripts/render.sh proxy                 /srv/proxy                  ACME_EMAIL=you@example.com
scripts/render.sh proxy-site/__APP__.caddy /srv/proxy/sites/myapp.caddy APP=myapp DOMAIN=myapp.example.com
scripts/render.sh mysql                 /srv/myapp-mysql            APP=myapp DB=myapp-mysql
scripts/render.sh redis                 /srv/myapp-redis            APP=myapp DB=myapp-redis
scripts/render.sh laravel/server        /srv/myapp                  APP=myapp DOMAIN=myapp.example.com
```

Then fill in the passwords in each `.env`, and start them in order: proxy,
databases, then the app (see [Deploy a new version by hand](#deploy-a-new-version-by-hand)).

| Placeholder | Meaning |
| --- | --- |
| `__APP__` | App name: lowercase letters, digits and dashes |
| `__DOMAIN__` | Domain(s) for the app, e.g. `shop.example.com, www.shop.example.com` |
| `__DB__` | Database name, by convention `<app>-mysql` or `<app>-redis` |
| `__ACME_EMAIL__` | Email for Let's Encrypt expiry notices |

## Manage an app by hand

Nothing on the server needs Lowol. For an app named `myapp`:

| Path | What it is |
| --- | --- |
| `/srv/myapp/compose.yml` | The app's containers: `web`, `worker`, `scheduler` |
| `/srv/myapp/.env` | Settings and secrets for all three |
| `/srv/myapp-mysql/` | MySQL and its nightly backups |
| `/srv/myapp-redis/` | Redis for sessions, cache and queues |
| `/srv/proxy/sites/myapp.caddy` | Which domain points at the app |

Run these from `/srv/myapp`:

```sh
docker compose ps                    # what is running
docker compose logs -f web           # follow the web logs (also: worker, scheduler)
docker compose restart               # restart all three
docker compose exec web php artisan tinker
```

To change a setting, edit `.env`, then run `docker compose up -d`.

### Deploy a new version by hand

1. Build the image from your repo, on the server or anywhere with Docker:

   ```sh
   git clone <your repo> /tmp/myapp && cd /tmp/myapp
   git checkout <commit>
   docker build -t myapp:<commit> .
   ```

   Built elsewhere? Copy it over:
   `docker save myapp:<commit> | ssh <server> docker load`

2. Run database migrations with the new image:

   ```sh
   cd /srv/myapp
   APP_TAG=<commit> docker compose run --rm --no-deps web php artisan migrate --force
   ```

3. Switch to it: set `APP_TAG=<commit>` in `.env`, then `docker compose up -d`.

4. Roll back: put the previous tag back in `.env` and run `docker compose up -d`.
   List the tags on the server with `docker image ls myapp`.

Remove old images with `docker image rm myapp:<old tag>`.

## Backups and restores

In `/srv/myapp-mysql`, `compose.yml` runs `mysql`, plus `backup` (nightly
dump) and `upload` (copy to object storage). `backup.env` holds the backup
time, how long to keep dumps and the object storage keys; after changing it,
run `docker compose up -d`.

- Every night at `BACKUP_HOUR` a compressed dump is written to the `backups`
  volume and kept for `BACKUP_KEEP_DAYS` days.
- If `BACKUP_BUCKET` is set, dumps are also copied to object storage every
  hour, under `BACKUP_PREFIX/`, and kept for `BACKUP_STORAGE_KEEP_DAYS` days.

Run these from `/srv/myapp-mysql`:

```sh
docker compose exec backup bash /scripts/backup.sh now     # back up now
docker compose exec backup ls -lh /backups                 # list dumps
docker compose logs backup upload                          # check they ran
```

Restoring replaces the current data. The script takes a fresh backup first:

```sh
docker compose exec backup bash /scripts/restore.sh <dump file name>
```

The dump is only in object storage? Bring it back first:

```sh
docker compose exec upload sh -c 'rclone copy "spaces:$BACKUP_BUCKET/$BACKUP_PREFIX/<dump file name>" /backups/'
```

To stop backups, remove the `backup` and `upload` services from
`compose.yml`, then run `docker compose up -d --remove-orphans`. Delete the
object storage key from your cloud account if nothing else uses it.

## Check the templates

```sh
tests/validate.sh
```

Renders every template, runs `docker compose config` on each, and runs
shellcheck and `caddy validate` when they are installed. The same checks run
on every push (`.github/workflows/validate.yml`).

## License

MIT
