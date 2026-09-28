#!/usr/bin/env bash
set -euo pipefail
TASK_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
python3 - "$TASK_ROOT/.local/cloud/secrets.env" <<'PY'
from pathlib import Path
import re, sys
values = dict(line.split('=', 1) for line in Path(sys.argv[1]).read_text().splitlines()
              if line.strip() and not line.lstrip().startswith('#') and '=' in line)
domain = values.get('DEMO_DOMAIN', '').strip()
email = values.get('ACME_EMAIL', '').strip()
if not re.fullmatch(r'[A-Za-z0-9](?:[A-Za-z0-9.-]*[A-Za-z0-9])?\.[A-Za-z]{2,}', domain) or domain.endswith('.invalid'):
    raise SystemExit('Set DEMO_DOMAIN to your DNS name (no scheme or path).')
if '@' not in email or email.endswith('.invalid'):
    raise SystemExit('Set ACME_EMAIL to your certificate contact email.')
PY
bash "$TASK_ROOT/scripts/cloud-compose.sh" --profile https up -d caddy
printf '%s\n' 'HTTPS proxy started. Confirm DNS and certificate issuance with cloud-compose.sh logs caddy.'
