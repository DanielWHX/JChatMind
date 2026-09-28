"""Start an isolated loopback guest demo using the existing local DB/model configuration.
Build first: cd jchatmind && JAVA_HOME=<JDK21> ./mvnw -DskipTests package
Requires the local PostgreSQL/Ollama services and prepared OrbitDesk demo data.
Does not stop existing services or change network/VPN settings.
"""
from pathlib import Path
import json, os, secrets, shutil, socket, subprocess, time

ROOT = Path(__file__).resolve().parents[1]
LOCAL = ROOT / '.local'
java = Path(os.environ.get('JCHATMIND_JAVA_HOME', '/Library/Java/JavaVirtualMachines/temurin-21.jdk/Contents/Home')) / 'bin/java'
jar = ROOT / 'jchatmind/target/jchatmind-0.0.1-SNAPSHOT.jar'
for file in [java, jar, LOCAL / 'config/application-local.yaml', LOCAL / 'business-demo.json']:
    if not file.exists():
        raise SystemExit(f'Missing prerequisite: {file}')
for port in [8081, 5177]:
    with socket.socket() as sock:
        if sock.connect_ex(('127.0.0.1', port)) == 0:
            raise SystemExit(f'Port {port} already in use; existing services were left untouched.')
state = json.loads((LOCAL / 'business-demo.json').read_text())
env = dict(os.environ)
env.update(JCHATMIND_ADMIN_SECRET=secrets.token_urlsafe(40),
           JCHATMIND_DEMO_SIGNING_SECRET=secrets.token_urlsafe(40),
           JCHATMIND_DEMO_AGENT_ID=state['agentId'], JCHATMIND_DEMO_KB_ID=state['knowledgeBaseId'],
           VITE_API_ORIGIN='')
(LOCAL / 'logs').mkdir(exist_ok=True)
(LOCAL / 'pids').mkdir(exist_ok=True)
commands = [
    ('guided-backend', ROOT / 'jchatmind', [str(java), '-jar', str(jar), '--spring.profiles.active=local,cloud',
     '--spring.config.additional-location=optional:file:' + str(LOCAL / 'config') + '/', '--server.address=127.0.0.1', '--server.port=8081']),
    ('guided-ui', ROOT / 'ui', [shutil.which('node'), str(ROOT / 'ui/node_modules/vite/bin/vite.js'), '--config', 'vite.guest.config.ts']),
]
for name, cwd, command in commands:
    with open(LOCAL / 'logs' / (name + '.log'), 'ab') as log:
        child = subprocess.Popen(command, cwd=cwd, env=env, stdin=subprocess.DEVNULL, stdout=log, stderr=log, start_new_session=True)
    time.sleep(.3)
    if child.poll() is not None:
        raise SystemExit(f'{name} exited; inspect .local/logs/{name}.log')
    started = subprocess.check_output(['ps', '-p', str(child.pid), '-o', 'lstart='], text=True).strip()
    record = LOCAL / 'pids' / (name + '.json')
    record.write_text(json.dumps({'pid': child.pid, 'started': started, 'directory': str(cwd), 'command': command}, indent=2))
    record.chmod(0o600)
print('Started guest preview: http://127.0.0.1:5177/demo (backend 8081). Readiness still needs verification.')
