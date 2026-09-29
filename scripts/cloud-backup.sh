#!/usr/bin/env bash
# Briefly stops API writes so PostgreSQL and uploaded documents agree.
# The resulting private backup contains credentials; never commit it.
set -euo pipefail
TASK_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cloud() { bash "$TASK_ROOT/scripts/cloud-compose.sh" "$@"; }
umask 077
backup="$TASK_ROOT/.local/backups/$(date -u +%Y%m%dT%H%M%SZ)"
mkdir -p "$backup"
api=$(cloud ps -q api)
test -n "$api"
documents=$(docker inspect --format '{{range .Mounts}}{{if eq .Destination "/app/data/documents"}}{{.Name}}{{end}}{{end}}' "$api")
test -n "$documents"
database_image=$(docker inspect --format '{{.Image}}' "$(cloud ps -q postgres)")
cloud stop api
trap 'cloud up -d --wait api web >&2' EXIT
cloud exec -T postgres pg_dump -U jchatmind -d jchatmind -Fc > "$backup/database.dump"
docker run --rm --network none --mount "type=volume,source=$documents,target=/documents,readonly" \
    --entrypoint tar "$database_image" -C /documents -czf - . > "$backup/documents.tar.gz"
tar -C "$TASK_ROOT" -czf "$backup/private-config.tar.gz" .local/cloud/secrets.env \
    .local/cloud/demo.env .local/cloud/admin-login.env .local/cloud/admin.htpasswd .local/cloud/seed.json
git -C "$TASK_ROOT" rev-parse HEAD > "$backup/source-commit.txt"
cloud images > "$backup/images.txt"
(cd "$backup" && sha256sum database.dump documents.tar.gz private-config.tar.gz > SHA256SUMS)
printf 'Private backup saved: %s\n' "$backup"
