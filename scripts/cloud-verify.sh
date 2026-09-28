#!/usr/bin/env bash
# Guest-session and access-boundary checks; deliberately no paid LLM request.
set -euo pipefail
TASK_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
python3 - "$TASK_ROOT" "$@" <<'PY'
from pathlib import Path
import argparse, base64, json, sys, urllib.error, urllib.parse, urllib.request, uuid

root = Path(sys.argv[1])
parser = argparse.ArgumentParser(description='Verify the cloud guest and optional admin boundaries without model calls.')
parser.add_argument('origin', nargs='?', default='')
parser.add_argument('--admin', action='store_true', help='Also verify the configured owner login; HTTPS/loopback only.')
options = parser.parse_args(sys.argv[2:])
supplied = options.origin
values = {}
config = root / '.local/cloud/secrets.env'
if config.exists():
    values = dict(line.split('=', 1) for line in config.read_text().splitlines()
                  if line.strip() and not line.lstrip().startswith('#') and '=' in line)
base = supplied.rstrip('/') or 'http://127.0.0.1:' + values.get('CLOUD_HTTP_PORT', '8082')
url = urllib.parse.urlparse(base)
if url.scheme not in ('http', 'https') or not url.hostname or url.username or url.password or url.path or url.query or url.fragment:
    raise SystemExit('Pass an HTTP(S) origin without embedded credentials.')

class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None

opener = urllib.request.build_opener(NoRedirect())

def request(path, method='GET', body=None, token=None, extra_headers=None, stream=False):
    headers = {'Content-Type': 'application/json'}
    if token:
        headers['Authorization'] = 'Bearer ' + token
    headers.update(extra_headers or {})
    req = urllib.request.Request(base + path, method=method, headers=headers,
                                 data=None if body is None else json.dumps(body).encode())
    try:
        response = opener.open(req, timeout=20)
    except urllib.error.HTTPError as error:
        response = error
    with response:
        if stream:
            lines = []
            for _ in range(8):
                line = response.readline(2048).decode()
                lines.append(line)
                if not line.strip():
                    break
            return response.status, response.headers, ''.join(lines)
        return response.status, response.headers, response.read().decode()

status, headers, body = request('/demo')
assert status == 200 and '<div id="root">' in body, 'Demo UI did not load.'
assert "frame-ancestors 'self'" in headers.get('Content-Security-Policy', ''), 'Embedding policy is absent.'
for path in ['/', '/chat/check', '/api/agents', '/api/chat-sessions', '/api/knowledge-bases', '/api/documents', '/api/tools', '/sse/connect/not-a-session']:
    status, response_headers, _ = request(path)
    assert status == 401, f'Unauthenticated admin route was not rejected: {path} ({status})'
    assert response_headers.get('WWW-Authenticate', '').startswith('Basic '), 'Browser admin authentication is absent.'
status, _, _ = request('/api/agents', extra_headers={'X-JChatMind-Admin': 'forged'})
assert status == 401, 'A caller-supplied admin header bypassed browser authentication.'
status, _, _ = request('/api/demo/session', token='invalid')
assert status == 401, 'An invalid guest token was accepted.'
status, _, body = request('/api/demo/sessions', method='POST', body={})
assert status == 200, f'Guest creation failed ({status}); ensure cloud-seed.sh ran and the API was recreated.'
session = json.loads(body)
assert session['sessionToken'] and session['maxTurns'] > 0 and session['expiresAt']
status, _, body = request('/api/demo/session', token=session['sessionToken'])
assert status == 200, 'Guest could not read its own session.'
state = json.loads(body)
assert state['status'] == 'idle' and state['messages'] == [] and state['remainingTurns'] > 0
print('PASS: demo UI, iframe policy, admin rejection, invalid token rejection and isolated guest session.')
if options.admin:
    loopback = url.hostname in ('127.0.0.1', 'localhost', '::1')
    configured_domain = values.get('DEMO_DOMAIN', '').strip()
    if not loopback and not (url.scheme == 'https' and url.netloc == configured_domain):
        raise SystemExit('Admin verification only sends credentials to loopback or the configured HTTPS DEMO_DOMAIN.')
    login = dict(line.split('=', 1) for line in (root / '.local/cloud/admin-login.env').read_text().splitlines()
                 if line and not line.startswith('#') and '=' in line)
    auth = 'Basic ' + base64.b64encode((login['JCHATMIND_ADMIN_USERNAME'] + ':' + login['JCHATMIND_ADMIN_PASSWORD']).encode()).decode()
    headers = {'Authorization': auth}
    status, _, _ = request('/', extra_headers=headers)
    assert status == 200, 'Authenticated original application did not load.'
    for path in ['/api/agents', '/api/knowledge-bases', '/api/chat-sessions', '/api/documents']:
        status, _, body = request(path, extra_headers=headers)
        assert status == 200 and json.loads(body).get('code') == 200, 'Authenticated admin API failed: ' + path
    # This connects an unused ephemeral stream; it neither reads an existing
    # user's stream nor writes a database session or calls an Agent.
    status, response_headers, body = request('/sse/connect/cloud-check-' + uuid.uuid4().hex,
                                           extra_headers=headers, stream=True)
    assert status == 200 and 'text/event-stream' in response_headers.get('Content-Type', '')
    assert 'connected' in body, 'Authenticated SSE did not initialize.'
    print('PASS: original administrator UI, Agent/KB/document/history APIs and native SSE authentication.')
print('No model request was made. A live handbook question still needs one end-to-end check before release.')
PY
