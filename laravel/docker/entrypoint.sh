#!/bin/sh
# Runs before every process started from this image (web, worker, scheduler,
# release command). Caches config, routes, events and views from the current
# environment variables, then hands over to the real command.
set -e

if [ "${SKIP_OPTIMIZE:-0}" != "1" ]; then
    php artisan package:discover --ansi > /dev/null
    php artisan optimize
fi

exec "$@"
