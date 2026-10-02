# lowol-templates

The files Lowol writes to your server, in the open. Everything here is plain
Docker and Docker Compose: if you stop using Lowol, your server keeps running
these files exactly as they are, and you can manage them by hand.

## What's here

| Folder | Goes to | What it is |
| --- | --- | --- |
| `laravel/Dockerfile`, `laravel/.dockerignore`, `laravel/docker/` | your repo | Production image for a Laravel app (FrankenPHP, PHP 8.4) |
| `laravel/server/` | `/srv/<app>/` | Compose file for `web`, `worker` and `scheduler`, plus `.env` and a README |
| `proxy/` | `/srv/proxy/` | Caddy on ports 80/443 with automatic HTTPS, shared by all apps on the server |
| `proxy-site/` | `/srv/proxy/sites/<app>.caddy` | Points a domain at one app |
| `mysql/` | `/srv/<app>-mysql/` | MySQL 8.4 (or 8.0, set in `.env`) with nightly backups to object storage |
| `redis/` | `/srv/<app>-redis/` | Redis 7 for sessions, cache and queues |
| `scripts/render.sh` | — | Fills in the `__PLACEHOLDERS__` (what Lowol does when it writes these files) |
| `scripts/try-local.sh` | — | Runs the whole setup on your own machine |

On a server it looks like this:

```
/srv/proxy/                  Caddy; sites/<app>.caddy per app
/srv/myapp/                  compose.yml, .env, README.md
/srv/myapp-mysql/            compose.yml, .env, backup.env, scripts/, README.md
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

## Render files yourself

```sh
scripts/render.sh proxy                 /srv/proxy                  ACME_EMAIL=you@example.com
scripts/render.sh proxy-site/__APP__.caddy /srv/proxy/sites/myapp.caddy APP=myapp DOMAIN=myapp.example.com
scripts/render.sh mysql                 /srv/myapp-mysql            APP=myapp DB=myapp-mysql
scripts/render.sh redis                 /srv/myapp-redis            APP=myapp DB=myapp-redis
scripts/render.sh laravel/server        /srv/myapp                  APP=myapp DOMAIN=myapp.example.com
```

Then fill in the passwords in each `.env`, and start them in order: proxy,
databases, then the app (see `/srv/myapp/README.md`).

| Placeholder | Meaning |
| --- | --- |
| `__APP__` | App name: lowercase letters, digits and dashes |
| `__DOMAIN__` | Domain(s) for the app, e.g. `shop.example.com, www.shop.example.com` |
| `__DB__` | Database name, by convention `<app>-mysql` or `<app>-redis` |
| `__ACME_EMAIL__` | Email for Let's Encrypt expiry notices |

## Check the templates

```sh
tests/validate.sh
```

Renders every template, runs `docker compose config` on each, and runs
shellcheck and `caddy validate` when they are installed. The same checks run
on every push (`.github/workflows/validate.yml`).

## License

MIT
