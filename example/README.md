# Example app

A fresh Laravel app with the files from `laravel/` (Dockerfile, `.dockerignore`,
`docker/`) and one status page. Use it to try Lowol, or the setup in this repo,
without bringing your own app.

The page at `/` shows each part of the setup working:

| Check | Works when |
| --- | --- |
| Version | the image tag the server runs (`APP_TAG`), which Lowol sets to the commit |
| MySQL | the app reaches its database and migrations ran |
| Redis | the cache answers; it counts page views |
| Scheduler | the `scheduler` container ran the heartbeat in the last minute |
| Queue worker | the `worker` container processed the job the scheduler queued |

The page always answers 200, so a broken database shows on the page instead of
failing the deploy's health check.

`/status.json` returns the same checks for scripts.

## Nightly test versions

Lowol's nightly test deploys this app, then two broken versions of it, each
one commit on top of `dev`:

| Branch | What's wrong | Lowol should |
| --- | --- | --- |
| `nightly/broken` | `/` answers 500 | fail the deploy's check and keep the running version |
| `nightly/crash` | the queue worker exits on its first job, about a minute after going live | notice the crash and go back to the version before |

After changing the app, move both branches onto `dev` again:
`git rebase dev nightly/broken && git rebase dev nightly/crash`.

## Deploy it with Lowol

Create an app with:

- **Repository:** `https://github.com/kelek-app/lowol-templates`
- **Branch:** `dev`
- **Root directory:** `example`
- **Release command:** `php artisan migrate --force`
- **Databases:** MySQL and Redis

## Run it on your machine

From the repo root: `scripts/try-local.sh up example`, then open
http://localhost:8080. The scheduler and worker show up within a minute.

## Change it

`laravel/` is the source of the Docker files. After changing them there, copy
them here again; `tests/validate.sh` checks that they match.
