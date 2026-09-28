#!/usr/bin/env bash
set -euo pipefail
TASK_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cloud() { bash "$TASK_ROOT/scripts/cloud-compose.sh" "$@"; }
cloud config --quiet
cloud up -d --wait postgres ollama
printf '%s\n' 'Preparing the bge-m3 embedding model (the first download may take several minutes)…'
cloud exec -T ollama ollama pull bge-m3
cloud up -d --build --wait api web
bash "$TASK_ROOT/scripts/cloud-seed.sh"
# docker compose reloads the generated IDs; an ordinary restart would keep old env.
cloud up -d --wait api web
printf '%s\n' 'Cloud stack is ready on its localhost HTTP port. Run cloud-verify.sh, then cloud-https.sh once DNS is ready.'
