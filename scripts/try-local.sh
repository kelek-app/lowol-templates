#!/usr/bin/env bash
# Runs a Laravel app on your own machine exactly the way a server would:
# proxy + app (web, worker, scheduler) + MySQL with backups + Redis.
#
#   scripts/try-local.sh up   <path to your Laravel app>   # build and start
#   scripts/try-local.sh down                              # stop and delete everything
#
# Needs Docker with Compose v2. The app opens at http://localhost:8080
# (change with LOCAL_PORT=9000). Rendered server files go to ./.try/ so you can
# read exactly what a server would get.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TRY="$ROOT/.try"
APP="${APP:-demo}"
LOCAL_PORT="${LOCAL_PORT:-8080}"
RENDER="$ROOT/scripts/render.sh"

say() { printf '\n==> %s\n' "$*"; }

set_env() {  # <file> <KEY> <value>: set KEY=value, adding the line if missing
    if grep -q "^$2=" "$1"; then
        KEY="$2" VALUE="$3" perl -i -pe 's/^\Q$ENV{KEY}\E=.*/$ENV{KEY}=$ENV{VALUE}/' "$1"
    else
        printf '%s=%s\n' "$2" "$3" >> "$1"
    fi
}

down() {
    say "Stopping and removing everything from $TRY"
    for dir in "$TRY/$APP" "$TRY/$APP-redis" "$TRY/$APP-mysql" "$TRY/proxy"; do
        [[ -f "$dir/compose.yml" ]] && (cd "$dir" && docker compose down -v --remove-orphans)
    done
    rm -rf "$TRY"
    echo "Done. The image $APP:local is kept; remove it with: docker image rm $APP:local"
}

up() {
    local app_dir="${1:?usage: try-local.sh up <path to your Laravel app>}"
    app_dir="$(cd "$app_dir" && pwd)"
    [[ -f "$app_dir/artisan" ]] || { echo "No artisan file in $app_dir: is it a Laravel app?" >&2; exit 1; }
    [[ -e "$TRY" ]] && { echo "$TRY exists. Run '$0 down' first." >&2; exit 1; }

    say "Checking the app has the Dockerfile from this repo"
    for f in Dockerfile .dockerignore docker; do
        if [[ ! -e "$app_dir/$f" ]]; then
            cp -R "$ROOT/laravel/$f" "$app_dir/$f"
            echo "copied $f into $app_dir"
        fi
    done

    say "Building $APP:local"
    docker build -t "$APP:local" "$app_dir"

    local mysql_pw root_pw redis_pw app_key
    mysql_pw="$(openssl rand -hex 16)"
    root_pw="$(openssl rand -hex 16)"
    redis_pw="$(openssl rand -hex 16)"
    app_key="$(docker run --rm -e SKIP_OPTIMIZE=1 "$APP:local" php artisan key:generate --show)"

    say "Rendering server files into $TRY"
    mkdir -p "$TRY"
    "$RENDER" "$ROOT/proxy" "$TRY/proxy" ACME_EMAIL=local@example.com
    "$RENDER" "$ROOT/proxy-site/__APP__.caddy" "$TRY/proxy/sites/$APP.caddy" APP="$APP" DOMAIN="http://localhost"
    "$RENDER" "$ROOT/mysql" "$TRY/$APP-mysql" APP="$APP" DB="$APP-mysql"
    "$RENDER" "$ROOT/redis" "$TRY/$APP-redis" APP="$APP" DB="$APP-redis"
    "$RENDER" "$ROOT/laravel/server" "$TRY/$APP" APP="$APP" DOMAIN="localhost"

    # Local differences from a real server: one HTTP port, no TLS, no object storage.
    perl -i -ne 'next if /"443:443/; s/"80:80"/"'"$LOCAL_PORT"':80"/; print' "$TRY/proxy/compose.yml"
    set_env "$TRY/$APP-mysql/.env" MYSQL_PASSWORD "$mysql_pw"
    set_env "$TRY/$APP-mysql/.env" MYSQL_ROOT_PASSWORD "$root_pw"
    set_env "$TRY/$APP-redis/.env" REDIS_PASSWORD "$redis_pw"
    set_env "$TRY/$APP/.env" APP_TAG local
    set_env "$TRY/$APP/.env" APP_KEY "$app_key"
    set_env "$TRY/$APP/.env" APP_URL "http://localhost:$LOCAL_PORT"
    set_env "$TRY/$APP/.env" DB_PASSWORD "$mysql_pw"
    set_env "$TRY/$APP/.env" REDIS_PASSWORD "$redis_pw"
    set_env "$TRY/$APP/.env" FILESYSTEM_DISK local

    say "Starting proxy, MySQL and Redis"
    (cd "$TRY/proxy" && docker compose up -d)
    (cd "$TRY/$APP-mysql" && docker compose up -d --wait mysql && docker compose up -d)
    (cd "$TRY/$APP-redis" && docker compose up -d --wait)

    say "Running the release command (migrations)"
    (cd "$TRY/$APP" && docker compose run --rm --no-deps web php artisan migrate --force)

    say "Starting $APP"
    (cd "$TRY/$APP" && docker compose up -d --wait)

    say "Ready: http://localhost:$LOCAL_PORT"
    cat <<EOF
Try:
  cd $TRY/$APP && docker compose logs -f web
  cd $TRY/$APP-mysql && docker compose exec backup bash /scripts/backup.sh now
  $0 down
EOF
}

case "${1:-}" in
    up) shift; up "$@" ;;
    down) down ;;
    *) sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'; exit 2 ;;
esac
