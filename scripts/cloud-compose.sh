#!/usr/bin/env bash
# Always select the cloud project explicitly; never touch compose.yaml/local data.
set -euo pipefail
TASK_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
for filename in secrets.env demo.env; do
    if [[ ! -f "$TASK_ROOT/.local/cloud/$filename" ]]; then
        printf '%s\n' 'Run scripts/cloud-init.sh and configure .local/cloud/secrets.env first.' >&2
        exit 1
    fi
done
for filename in admin-login.env admin.htpasswd; do
    if [[ ! -f "$TASK_ROOT/.local/cloud/$filename" ]]; then
        printf '%s\n' 'Run scripts/cloud-init.sh to create the separate browser admin login first.' >&2
        exit 1
    fi
done
exec docker compose --project-directory "$TASK_ROOT" \
    --env-file "$TASK_ROOT/.local/cloud/secrets.env" \
    --env-file "$TASK_ROOT/.local/cloud/demo.env" \
    -f "$TASK_ROOT/compose.cloud.yaml" "$@"
