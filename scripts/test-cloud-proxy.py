#!/usr/bin/env python3
"""Exercise the actual cloud Nginx template against a disposable inert upstream.

Uses only generated test credentials, localhost ports and a cached Docker image.
It never starts Java, accesses project data, or calls a model/provider.
"""
from pathlib import Path
import base64
import http.client
import json
import os
import secrets
import shutil
import subprocess
import tempfile
import time
import uuid

ROOT = Path(__file__).resolve().parents[1]
IMAGE = os.environ.get('CLOUD_PROXY_TEST_IMAGE', 'jchatmind-cloud-web:local')


def docker(*args):
    result = subprocess.run(['docker', *args], capture_output=True, text=True)
    if result.returncode:
        raise RuntimeError('Docker test operation failed: ' + result.stderr.strip())
    return result.stdout.strip()


def run():
    name = 'jchatmind-auth-test-' + uuid.uuid4().hex[:10]
    secret = secrets.token_hex(32)
    password = secrets.token_urlsafe(24)
    basic = 'Basic ' + base64.b64encode(('owner:' + password).encode()).decode()
    with tempfile.TemporaryDirectory(prefix='jchatmind-proxy-test-') as folder:
        fixture = Path(folder)
        # Upgrade an existing installation without modifying any original
        # runtime secret; also prove repeated init keeps the browser password.
        init_root = fixture / 'init-check'
        (init_root / 'scripts').mkdir(parents=True)
        private = init_root / '.local/cloud'
        private.mkdir(parents=True)
        previous = b'# Existing test configuration\nPRESERVE_THIS=unchanged\n'
        (private / 'secrets.env').write_bytes(previous)
        shutil.copyfile(ROOT / 'scripts/cloud-init.sh', init_root / 'scripts/cloud-init.sh')
        for index in range(2):
            result = subprocess.run(['bash', str(init_root / 'scripts/cloud-init.sh')], text=True, capture_output=True)
            assert result.returncode == 0, 'Cloud initialization failed in its isolated fixture.'
            assert (private / 'secrets.env').read_bytes() == previous
            current = ((private / 'admin-login.env').read_bytes(), (private / 'admin.htpasswd').read_bytes())
            if index == 0:
                initial = current
            else:
                assert current == initial, 'Rerunning cloud initialization changed administrator credentials.'
        assert (private / 'admin-login.env').stat().st_mode & 0o777 == 0o600
        assert (private / 'admin.htpasswd').stat().st_mode & 0o777 == 0o644
        html = fixture / 'html'
        (html / 'assets').mkdir(parents=True)
        html.chmod(0o755)
        (html / 'index.html').write_text('<div id="root">Test application</div>')
        (html / 'assets/app.js').write_text('// Test asset')
        hashed = subprocess.run(['openssl', 'passwd', '-apr1', '-stdin'], input=password + '\n',
                                text=True, capture_output=True, check=True).stdout.strip()
        password_file = fixture / 'admin.htpasswd'
        password_file.write_text('owner:' + hashed + '\n')
        password_file.chmod(0o644)
        entrypoint = fixture / '15-admin-auth-check.sh'
        entrypoint.write_bytes((ROOT / 'infra/cloud/15-admin-auth-check.sh').read_bytes())
        entrypoint.chmod(0o755)
        stub = fixture / 'upstream.conf'
        stub.write_text('''server {
    listen 8080;
    server_name api;
    location /sse/ {
        default_type text/event-stream;
        return 200 'event: init\\ndata: {"path":"$request_uri","admin":"$http_x_jchatmind_admin","authorization":"$http_authorization"}\\n\\n';
    }
    location / {
        default_type application/json;
        return 200 '{"path":"$request_uri","admin":"$http_x_jchatmind_admin","authorization":"$http_authorization"}';
    }
}
''')
        started = False
        try:
            docker('run', '-d', '--name', name, '--add-host', 'api:127.0.0.1',
                   '-p', '127.0.0.1::80',
                   '-e', 'PORTFOLIO_ORIGIN=https://portfolio.example',
                   '-e', 'JCHATMIND_ADMIN_SECRET=' + secret,
                   '-e', 'NGINX_ENVSUBST_FILTER=^(PORTFOLIO_ORIGIN|JCHATMIND_ADMIN_SECRET)$',
                   '-v', str(ROOT / 'infra/cloud/nginx.conf.template') + ':/etc/nginx/templates/default.conf.template:ro',
                   '-v', str(ROOT / 'infra/cloud/guest-proxy.conf') + ':/etc/nginx/snippets/guest-proxy.conf:ro',
                   '-v', str(entrypoint) + ':/docker-entrypoint.d/15-admin-auth-check.sh:ro',
                   '-v', str(password_file) + ':/etc/nginx/private/admin.htpasswd:ro',
                   '-v', str(stub) + ':/etc/nginx/conf.d/upstream.conf:ro',
                   '-v', str(html) + ':/usr/share/nginx/html:ro', IMAGE)
            started = True
            port = int(docker('port', name, '80/tcp').rsplit(':', 1)[1])

            def request(path, method='GET', headers=None):
                connection = http.client.HTTPConnection('127.0.0.1', port, timeout=5)
                connection.request(method, path, headers=headers or {})
                response = connection.getresponse()
                result = response.status, dict(response.getheaders()), response.read().decode()
                connection.close()
                return result

            for _ in range(60):
                try:
                    if request('/health')[0] == 200:
                        break
                except (OSError, http.client.HTTPException):
                    pass
                time.sleep(0.1)
            else:
                raise AssertionError('Disposable proxy did not become ready; inspect its local configuration.')

            docker('exec', name, 'nginx', '-t')
            status, headers, body = request('/demo')
            assert status == 200 and 'Test application' in body
            assert "frame-ancestors 'self' https://portfolio.example" in headers['Content-Security-Policy']
            assert request('/demo/')[0] == 308
            assert request('/assets/app.js')[0] == 200
            admin_paths = ['/', '/index.html', '/chat/example', '/api/agents', '/api/documents',
                           '/api/chat-sessions', '/sse/connect/example', '/api/demo/unknown',
                           '/api/demo/sessions/', '/api/demo/sessions;admin',
                           '/api/demo/../agents', '/api/demo/%2e%2e/agents', '//api//agents',
                           '/api/demo/sessions%2f..%2fagents']
            for path in admin_paths:
                status, headers, _ = request(path)
                assert status == 401, 'Anonymous admin path was not denied: ' + path
                assert headers.get('WWW-Authenticate', '').startswith('Basic ')
            assert request('/api/agents', headers={'X-JChatMind-Admin': secret})[0] == 401
            assert request('/api/agents', headers={'Authorization': 'Basic b3duZXI6d3Jvbmc='})[0] == 401
            for path, method in [('/api/demo/sessions', 'POST'), ('/api/demo/session', 'GET'), ('/api/demo/messages', 'POST')]:
                status, _, body = request(path, method, {'Authorization': 'Bearer test-guest', 'X-JChatMind-Admin': secret})
                observed = json.loads(body)
                assert status == 200 and observed == {'path': path, 'admin': '', 'authorization': 'Bearer test-guest'}
            assert json.loads(request('/health', headers={'X-JChatMind-Admin': secret})[2])['admin'] == ''
            for path, method in [('/api/agents?limit=1', 'GET'), ('/api/documents/upload', 'POST'),
                                 ('/api/agents/example', 'PATCH'), ('/api/chat-sessions/example', 'DELETE')]:
                status, _, body = request(path, method, {'Authorization': basic, 'X-JChatMind-Admin': 'forged'})
                assert status == 200 and json.loads(body) == {'path': path, 'admin': secret, 'authorization': ''}
            assert request('/', headers={'Authorization': basic})[0] == 200
            assert request('/chat/example', headers={'Authorization': basic})[0] == 200
            status, headers, body = request('/sse/connect/example', headers={'Authorization': basic})
            assert status == 200 and headers['Content-Type'].startswith('text/event-stream')
            assert json.loads(body.split('data: ', 1)[1].strip()) == {
                'path': '/sse/connect/example', 'admin': secret, 'authorization': ''}
            assert request('/api/agents', headers={'Authorization': basic, 'Origin': 'https://attacker.example'})[0] == 403
            assert request('/api/agents', headers={'Authorization': basic, 'Origin': f'http://127.0.0.1:{port}'})[0] == 200
            print('PASS: anonymous demo/assets; protected UI/API/SSE; malformed paths; forged headers; guest bearer isolation; admin proxy injection; upload paths; SSE; Origin checks.')
            print('All credentials and upstream responses stayed inside the disposable fixture. No model or real database was used.')
        finally:
            if started:
                docker('rm', '-f', name)


if __name__ == '__main__':
    run()
