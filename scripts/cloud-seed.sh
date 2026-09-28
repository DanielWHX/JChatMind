#!/usr/bin/env bash
set -euo pipefail
TASK_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
python3 - "$TASK_ROOT" <<'PY'
from pathlib import Path
import base64, hashlib, json, re, subprocess, sys, urllib.error, urllib.request, uuid

root = Path(sys.argv[1])
private = root / '.local/cloud'
config = {}
for line in (private / 'secrets.env').read_text().splitlines():
    if line.strip() and not line.lstrip().startswith('#') and '=' in line:
        key, value = line.split('=', 1)
        config[key.strip()] = value.strip().strip('"').strip("'")
admin = config.get('JCHATMIND_ADMIN_SECRET', '')
if len(admin) < 32:
    raise SystemExit('JCHATMIND_ADMIN_SECRET is missing or too short.')
login = dict(line.split('=', 1) for line in (private / 'admin-login.env').read_text().splitlines()
             if line and not line.startswith('#') and '=' in line)
basic = base64.b64encode((login['JCHATMIND_ADMIN_USERNAME'] + ':' + login['JCHATMIND_ADMIN_PASSWORD']).encode()).decode()
port = config.get('CLOUD_HTTP_PORT', '8082')
if not port.isdigit() or not 1 <= int(port) <= 65535:
    raise SystemExit('CLOUD_HTTP_PORT must be a valid port.')
base = f'http://127.0.0.1:{port}'

class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None

opener = urllib.request.build_opener(NoRedirect())

def request(path, data=None, method=None, content_type='application/json'):
    payload = data if isinstance(data, bytes) else None if data is None else json.dumps(data).encode()
    req = urllib.request.Request(base + path, data=payload, method=method, headers={
        'Authorization': 'Basic ' + basic, 'Content-Type': content_type,
    })
    try:
        with opener.open(req, timeout=180) as response:
            result = json.load(response)
    except urllib.error.HTTPError as error:
        raise SystemExit(f'Admin API {path} returned HTTP {error.code}; no credential was printed.') from None
    if result.get('code') != 200:
        raise SystemExit(f'Admin API {path} rejected the operation; inspect the cloud API log.')
    return result.get('data') or {}

def single_named(items, name):
    matches = [item for item in items if item['name'] == name]
    if len(matches) > 1:
        raise SystemExit(f'Duplicate cloud seed name: {name}. Resolve the duplicate before retrying.')
    return matches[0]['id'] if matches else None

kb_name = 'OrbitDesk Public Demo Handbook'
agent_name = 'OrbitDesk Public Demo'
kb = single_named(request('/api/knowledge-bases')['knowledgeBases'], kb_name)
if not kb:
    kb = request('/api/knowledge-bases', {
        'name': kb_name, 'description': 'Fictional SaaS handbook for the public portfolio demo.',
    })['knowledgeBaseId']
uuid.UUID(kb)
handbook = (root / 'docs/business-demo/orbitdesk-handbook.md').read_bytes()
digest = hashlib.sha256(handbook).hexdigest()
previous_file = private / 'seed.json'
previous = json.loads(previous_file.read_text()) if previous_file.exists() else {}
if previous.get('knowledgeBaseId') == kb and previous.get('handbookSha256', digest) != digest:
    raise SystemExit('The seeded handbook has changed. Review/re-index it before publishing updated source claims.')
filename = 'orbitdesk-handbook.md'
matches = [item for item in request('/api/documents/kb/' + kb)['documents'] if item['filename'] == filename]
if len(matches) > 1:
    raise SystemExit('Duplicate OrbitDesk handbook documents; resolve them before retrying.')
if not matches:
    boundary = 'jchatmind-' + uuid.uuid4().hex
    body = (f'--{boundary}\r\nContent-Disposition: form-data; name="kbId"\r\n\r\n{kb}\r\n'
            f'--{boundary}\r\nContent-Disposition: form-data; name="file"; filename="{filename}"\r\n'
            'Content-Type: text/markdown\r\n\r\n').encode() + handbook + f'\r\n--{boundary}--\r\n'.encode()
    document = request('/api/documents/upload', body, content_type='multipart/form-data; boundary=' + boundary)['documentId']
else:
    document = matches[0]['id']
uuid.UUID(document)

# This application swallows indexing failures after upload. Do not equate HTTP
# success with a usable knowledge base: check the real persisted indexed sections.
compose = ['bash', str(root / 'scripts/cloud-compose.sh')]
sql = f"SELECT count(*) FROM chunk_bge_m3 WHERE kb_id='{kb}'::uuid AND doc_id='{document}'::uuid AND embedding IS NOT NULL;"
result = subprocess.run(compose + ['exec', '-T', 'postgres', 'psql', '-U', 'jchatmind', '-d', 'jchatmind', '-Atc', sql],
                        check=True, capture_output=True, text=True)
expected = len(re.findall(rb'^# ', handbook, flags=re.MULTILINE))
if result.stdout.strip() != str(expected):
    raise SystemExit(f'Handbook indexing is incomplete: expected {expected} sections. Check Ollama/API logs; seed IDs were not published.')

agent = single_named(request('/api/agents')['agents'], agent_name)
settings = {
    'name': agent_name,
    'description': 'Fictional SaaS support: grounded answers, calculations, dates and unsent reply drafts.',
    'systemPrompt': (root / 'docs/business-demo/agent-prompt.txt').read_text(),
    'model': 'deepseek-chat', 'allowedTools': [], 'allowedKbs': [kb],
    'chatOptions': {'temperature': 0.3, 'topP': 1.0, 'messageLength': 20},
}
if agent:
    request('/api/agents/' + agent, settings, method='PATCH')
else:
    agent = request('/api/agents', settings)['agentId']
uuid.UUID(agent)
state = {'agentId': agent, 'knowledgeBaseId': kb, 'documentId': document,
         'handbookSha256': digest, 'indexedSections': expected}
previous_file.write_text(json.dumps(state, indent=2) + '\n')
previous_file.chmod(0o600)
env_file = private / 'demo.env'
env_file.write_text(f'JCHATMIND_DEMO_AGENT_ID={agent}\nJCHATMIND_DEMO_KB_ID={kb}\n')
env_file.chmod(0o600)
print(f'OrbitDesk seed verified: {expected} indexed sections. Demo IDs saved to .local/cloud/demo.env.')
print('Run cloud-compose.sh up -d --wait api web to load the returned IDs.')
PY
