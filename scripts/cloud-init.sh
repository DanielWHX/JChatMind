#!/usr/bin/env bash
set -euo pipefail
TASK_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
python3 - "$TASK_ROOT" <<'PY'
from pathlib import Path
import secrets, subprocess, sys

directory = Path(sys.argv[1]) / '.local/cloud'
directory.mkdir(parents=True, exist_ok=True, mode=0o700)
directory.chmod(0o700)
target = directory / 'secrets.env'
if target.exists():
    print('Keeping existing .local/cloud/secrets.env; no credentials changed.')
else:
    values = {
        'POSTGRES_PASSWORD': secrets.token_hex(24),
        'JCHATMIND_ADMIN_SECRET': secrets.token_hex(32),
        'JCHATMIND_DEMO_SIGNING_SECRET': secrets.token_hex(32),
        'DEEPSEEK_API_KEY': '',
        'PORTFOLIO_ORIGIN': 'https://hongxiang-wang-portfolio.danielwhx1017.chatgpt.site',
        'CLOUD_HTTP_PORT': '8082',
        'DEMO_DOMAIN': '',
        'ACME_EMAIL': '',
    }
    with target.open('x') as stream:
        stream.write('# Private runtime configuration. Never copy into an image or Git.\n')
        stream.writelines(f'{key}={value}\n' for key, value in values.items())
    target.chmod(0o600)
    print('Created private runtime configuration in .local/cloud/secrets.env.')
state = directory / 'demo.env'
if not state.exists():
    state.write_text('# Populated by cloud-seed.sh after the real API returns IDs.\n')
    state.chmod(0o600)

# Separate browser credentials from the upstream API secret. Existing runtime
# secrets and existing administrator passwords are never replaced on rerun.
login = directory / 'admin-login.env'
if not login.exists():
    with login.open('x') as stream:
        stream.write('JCHATMIND_ADMIN_USERNAME=owner\n')
        stream.write('JCHATMIND_ADMIN_PASSWORD=' + secrets.token_urlsafe(24) + '\n')
    login.chmod(0o600)
    print('Created browser login in .local/cloud/admin-login.env; credentials were not printed.')
credentials = dict(line.split('=', 1) for line in login.read_text().splitlines()
                   if line and not line.startswith('#') and '=' in line)
username = credentials.get('JCHATMIND_ADMIN_USERNAME', '')
password = credentials.get('JCHATMIND_ADMIN_PASSWORD', '')
if not username or ':' in username or any(c.isspace() for c in username) or len(password) < 20:
    raise SystemExit('Invalid administrator login configuration; existing files were not replaced.')
htpasswd = directory / 'admin.htpasswd'
if not htpasswd.exists():
    result = subprocess.run(['openssl', 'passwd', '-apr1', '-stdin'], input=password + '\n',
                            text=True, capture_output=True, check=True)
    with htpasswd.open('x') as stream:
        stream.write(username + ':' + result.stdout.strip() + '\n')
    # The parent folder stays 700; the hash alone must be readable by Nginx's
    # unprivileged worker inside the read-only bind mount.
    htpasswd.chmod(0o644)
    print('Created read-only administrator password hash for Nginx.')
print('Set DEEPSEEK_API_KEY before starting. Set DEMO_DOMAIN and ACME_EMAIL before enabling HTTPS.')
PY
