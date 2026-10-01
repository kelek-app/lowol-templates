#!/usr/bin/env bash
# Checks every template without starting anything:
#   1. renders each template with sample values (no placeholder left over)
#   2. docker compose config on each rendered compose.yml
#   3. shellcheck on all shell scripts (if installed)
#   4. caddy validate on the proxy config (if caddy is installed)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$(mktemp -d)"
trap 'rm -rf "$OUT"' EXIT
RENDER="$ROOT/scripts/render.sh"
fail=0

step() { printf '\n--- %s\n' "$*"; }
ok() { printf 'ok   %s\n' "$*"; }
bad() { printf 'FAIL %s\n' "$*"; fail=1; }

step "Render templates"
"$RENDER" "$ROOT/proxy" "$OUT/proxy" ACME_EMAIL=ops@example.com
"$RENDER" "$ROOT/proxy-site/__APP__.caddy" "$OUT/proxy/sites/shop.caddy" APP=shop DOMAIN="shop.example.com, www.shop.example.com"
"$RENDER" "$ROOT/laravel/server" "$OUT/shop" APP=shop DOMAIN=shop.example.com
"$RENDER" "$ROOT/mysql" "$OUT/shop-mysql" APP=shop DB=shop-mysql
"$RENDER" "$ROOT/redis" "$OUT/shop-redis" APP=shop DB=shop-redis
[[ -f "$OUT/shop/.env" && -f "$OUT/shop-mysql/backup.env" ]] && ok ".env files named correctly" || bad ".env files"
if "$RENDER" "$ROOT/laravel/server" "$OUT/missing" APP=shop >/dev/null 2>&1; then
    bad "render should fail when DOMAIN is missing"
else
    ok "render refuses unfilled placeholders"
fi

step "docker compose config"
if command -v docker >/dev/null && docker compose version >/dev/null 2>&1; then
    printf 'APP_TAG=test\n' >> "$OUT/shop/.env"
    for dir in proxy shop shop-mysql shop-redis; do
        if (cd "$OUT/$dir" && docker compose config --quiet); then ok "$dir/compose.yml"; else bad "$dir/compose.yml"; fi
    done
    names="$(cd "$OUT/shop" && docker compose config --format json | grep -o '"container_name"' || true)"
    [[ -z "$names" ]] && ok "no fixed container names" || bad "container_name should not be set"
else
    echo "skip (docker compose not installed)"
fi

step "shellcheck"
if command -v shellcheck >/dev/null; then
    for f in "$ROOT"/scripts/*.sh "$ROOT"/tests/*.sh "$ROOT"/mysql/scripts/*.sh "$ROOT"/laravel/docker/entrypoint.sh; do
        if shellcheck "$f"; then ok "${f#"$ROOT"/}"; else bad "${f#"$ROOT"/}"; fi
    done
else
    echo "shellcheck not installed; checking syntax only"
    for f in "$ROOT"/scripts/*.sh "$ROOT"/tests/*.sh "$ROOT"/mysql/scripts/backup.sh "$ROOT"/mysql/scripts/restore.sh; do
        if bash -n "$f"; then ok "${f#"$ROOT"/} (syntax)"; else bad "${f#"$ROOT"/}"; fi
    done
    for f in "$ROOT"/mysql/scripts/upload.sh "$ROOT"/laravel/docker/entrypoint.sh; do
        if sh -n "$f"; then ok "${f#"$ROOT"/} (syntax)"; else bad "${f#"$ROOT"/}"; fi
    done
fi

step "caddy validate"
if command -v caddy >/dev/null; then
    if (cd "$OUT/proxy" && caddy validate --config Caddyfile --adapter caddyfile >/dev/null 2>&1); then
        ok "proxy Caddyfile with one site"
    else
        bad "proxy Caddyfile with one site"
        (cd "$OUT/proxy" && caddy validate --config Caddyfile --adapter caddyfile) || true
    fi
    rm "$OUT/proxy/sites/shop.caddy"
    if (cd "$OUT/proxy" && caddy validate --config Caddyfile --adapter caddyfile >/dev/null 2>&1); then
        ok "proxy Caddyfile with no sites yet"
    else
        bad "proxy Caddyfile with no sites yet"
    fi
else
    echo "skip (caddy not installed)"
fi

echo
if (( fail )); then echo "Some checks failed."; exit 1; fi
echo "All checks passed."
