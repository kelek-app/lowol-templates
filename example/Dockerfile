# Production image for a Laravel app.
#
# FrankenPHP serves HTTP on $PORT (default 8080). The same image runs the
# web server, the queue worker and the scheduler; only the command differs
# (see server/compose.yml).
#
# Copy this file, .dockerignore and the docker/ folder into the root of your
# Laravel repo, then:  docker build -t myapp:local .

# Match the PHP version your composer.lock was created with (php -v locally).
ARG PHP_VERSION=8.4
ARG NODE_VERSION=22

# --- PHP base: the same PHP and extensions at build time and at run time -----
FROM dunglas/frankenphp:1-php${PHP_VERSION} AS php-base
RUN install-php-extensions pdo_mysql redis pcntl bcmath intl zip opcache exif gd \
 && cp "$PHP_INI_DIR/php.ini-production" "$PHP_INI_DIR/php.ini"

FROM node:${NODE_VERSION}-bookworm-slim AS node

# --- 1. PHP dependencies for production --------------------------------------
FROM composer:2 AS vendor
WORKDIR /app
COPY composer.json composer.lock ./
RUN --mount=type=cache,target=/tmp/composer-cache \
    COMPOSER_CACHE_DIR=/tmp/composer-cache \
    composer install --no-dev --no-interaction --prefer-dist \
        --no-scripts --no-autoloader --ignore-platform-reqs
COPY . .
RUN composer dump-autoload --no-dev --optimize --no-scripts

# --- 2. Front-end assets (Vite) ----------------------------------------------
# This stage has PHP as well as Node: Vite plugins such as Laravel Wayfinder run
# `php artisan` during the build. It installs dev dependencies too; none of
# them reach the final image.
FROM php-base AS assets
COPY --from=node /usr/local/bin/node /usr/local/bin/node
COPY --from=node /usr/local/lib/node_modules /usr/local/lib/node_modules
RUN ln -s ../lib/node_modules/npm/bin/npm-cli.js /usr/local/bin/npm \
 && ln -s ../lib/node_modules/npm/bin/npx-cli.js /usr/local/bin/npx
COPY --from=composer:2 /usr/bin/composer /usr/bin/composer
WORKDIR /app
COPY composer.json composer.lock ./
RUN --mount=type=cache,target=/tmp/composer-cache \
    COMPOSER_CACHE_DIR=/tmp/composer-cache \
    composer install --no-interaction --prefer-dist --no-scripts --no-autoloader
COPY package*.json ./
RUN --mount=type=cache,target=/root/.npm \
    if [ -f package-lock.json ]; then npm ci; else npm install; fi
COPY . .
RUN composer dump-autoload --no-scripts \
 && npm run build

# --- 3. Runtime ---------------------------------------------------------------
FROM php-base AS app

COPY docker/php.ini "$PHP_INI_DIR/conf.d/zz-app.ini"
COPY docker/Caddyfile /etc/app/Caddyfile
COPY --chmod=0755 docker/entrypoint.sh /usr/local/bin/app-entrypoint

WORKDIR /app
COPY --from=vendor /app /app
COPY --from=assets /app/public/build /app/public/build

# Run as an unprivileged user. Only storage/, bootstrap/cache/ and Caddy's own
# state folders need to be writable.
RUN useradd --create-home --uid 1000 app \
 && mkdir -p storage/framework/cache storage/framework/sessions storage/framework/views \
             storage/logs bootstrap/cache /data/caddy /config/caddy \
 && chown -R app:app storage bootstrap/cache /data/caddy /config/caddy
USER app

ENV PORT=8080
EXPOSE 8080

# The base image checks FrankenPHP's admin endpoint, which is turned off here and
# does not exist in the worker or scheduler. Health is checked per process in
# compose.yml instead (the web container checks GET /).
HEALTHCHECK NONE

ENTRYPOINT ["app-entrypoint"]
CMD ["frankenphp", "run", "--config", "/etc/app/Caddyfile"]
