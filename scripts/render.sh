#!/usr/bin/env bash
# Renders a template file or folder by replacing __KEY__ placeholders.
#
#   scripts/render.sh <template> <output> KEY=VALUE [KEY=VALUE...]
#
# - Placeholders are replaced in file contents and in file names.
# - "*.env.example" files are written as "*.env" (".env.example" -> ".env").
# - Fails if any __PLACEHOLDER__ is left unfilled, or if <output> exists.
#
# This is the reference for what Lowol's deploy engine does when it writes
# files to a server. Example:
#   scripts/render.sh laravel/server /srv/myapp APP=myapp DOMAIN=myapp.example.com
set -euo pipefail

if (( $# < 2 )); then
    sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'
    exit 2
fi

src="$1"
out="$2"
shift 2

[[ -e "$src" ]] || { echo "render: no such template: $src" >&2; exit 1; }
[[ -e "$out" ]] && { echo "render: $out already exists; refusing to overwrite" >&2; exit 1; }

for pair in "$@"; do
    key="${pair%%=*}"
    value="${pair#*=}"
    if [[ ! "$key" =~ ^[A-Z][A-Z0-9_]*$ || "$pair" != *=* ]]; then
        echo "render: bad argument '$pair' (expected KEY=VALUE, KEY in capitals)" >&2
        exit 1
    fi
    export "RENDER_VAR_${key}=${value}"
done

substitute() {  # replaces __KEY__ in stdin using RENDER_VAR_KEY
    perl -pe 's/__([A-Z][A-Z0-9_]*)__/exists $ENV{"RENDER_VAR_$1"} ? $ENV{"RENDER_VAR_$1"} : $&/ge'
}

render_file() {  # <source file> <destination file>
    mkdir -p "$(dirname "$2")"
    substitute < "$1" > "$2"
    [[ -x "$1" ]] && chmod +x "$2"
    return 0
}

if [[ -f "$src" ]]; then
    render_file "$src" "$out"
else
    while IFS= read -r -d '' file; do
        rel="${file#"$src"/}"
        rel="$(printf '%s' "$rel" | substitute)"
        case "$rel" in
            .env.example) rel=".env" ;;
            */.env.example) rel="${rel%.example}" ;;
            *.env.example) rel="${rel%.example}" ;;
        esac
        render_file "$file" "$out/$rel"
    done < <(find "$src" -type f ! -name .gitkeep -print0)
    mkdir -p "$out"
    # Keep empty folders such as proxy/sites.
    while IFS= read -r -d '' dir; do
        mkdir -p "$out/${dir#"$src"/}"
    done < <(find "$src" -mindepth 1 -type d -print0)
fi

leftover="$(grep -rnoE '__[A-Z][A-Z0-9_]*__' "$out" || true)"
if [[ -n "$leftover" ]]; then
    echo "render: these placeholders were not filled:" >&2
    echo "$leftover" >&2
    exit 1
fi

echo "render: wrote $out"
