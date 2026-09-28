#!/bin/sh
set -eu
# Only configuration-safe opaque tokens may be substituted into an Nginx
# directive. Print field names, never credential values, on failure.
if ! printf '%s' "${JCHATMIND_ADMIN_SECRET:-}" | grep -Eq '^[A-Za-z0-9_-]{32,128}$'; then
    printf '%s\n' 'JCHATMIND_ADMIN_SECRET must be 32-128 URL-safe characters.' >&2
    exit 1
fi
if [ ! -s /etc/nginx/private/admin.htpasswd ]; then
    printf '%s\n' 'Missing administrator login file; run scripts/cloud-init.sh.' >&2
    exit 1
fi
if ! printf '%s' "${PORTFOLIO_ORIGIN:-}" | grep -Eq '^https?://[A-Za-z0-9.-]+(:[0-9]+)?$'; then
    printf '%s\n' 'PORTFOLIO_ORIGIN must be an HTTP(S) origin without a path.' >&2
    exit 1
fi
