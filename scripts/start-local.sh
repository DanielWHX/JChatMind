#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
LOCAL="$ROOT/.local"
LOGS="$LOCAL/logs"
PIDS="$LOCAL/pids"
JCHATMIND_JAVA_HOME=${JCHATMIND_JAVA_HOME:-/Library/Java/JavaVirtualMachines/temurin-21.jdk/Contents/Home}
JCHATMIND_OLLAMA_BIN=${JCHATMIND_OLLAMA_BIN:-/Applications/Ollama.app/Contents/Resources/ollama}
mkdir -p "$LOGS" "$PIDS"

fail() { printf '%s\n' "$*" >&2; exit 1; }
for executable in curl python3 docker lsof; do
  command -v "$executable" >/dev/null || fail "Missing command: $executable"
done
[[ -f "$ROOT/.env.local" ]] || fail 'Missing .env.local; see LOCAL-SETUP.md.'
[[ -f "$LOCAL/config/application-local.yaml" ]] || fail 'Missing .local/config/application-local.yaml; see LOCAL-SETUP.md.'

port_busy() { lsof -nP -iTCP:"$1" -sTCP:LISTEN >/dev/null 2>&1; }
backend_ready() {
  [[ $(curl -fsS --max-time 3 http://127.0.0.1:8080/health 2>/dev/null) == ok ]] &&
    curl -fsS --max-time 3 http://127.0.0.1:8080/api/agents 2>/dev/null |
    python3 -c 'import json,sys; d=json.load(sys.stdin); sys.exit(0 if d.get("code")==200 and isinstance(d.get("data",{}).get("agents"),list) else 1)' 2>/dev/null
}
frontend_ready() {
  curl -fsS --max-time 3 http://127.0.0.1:5174/ 2>/dev/null |
    python3 -c 'import sys; sys.exit(0 if "<title>JChatMind</title>" in sys.stdin.read() else 1)'
}
ollama_ready() {
  curl -fsS --max-time 3 http://127.0.0.1:11434/api/tags 2>/dev/null |
    python3 -c 'import json,sys; d=json.load(sys.stdin); sys.exit(0 if isinstance(d.get("models"),list) else 1)' 2>/dev/null
}
wait_for() {
  local name=$1 check=$2 attempt
  for attempt in {1..60}; do
    if "$check"; then return 0; fi
    sleep 2
  done
  fail "$name did not become ready. Check $LOGS; this script has not stopped other services."
}

# A separate process group and start-time record let stop-local identify only
# processes created here. Existing services are never adopted into these records.
launch() {
  local name=$1 directory=$2
  shift 2
  python3 - "$PIDS/$name.json" "$LOGS/$name.log" "$directory" "$@" <<'PY'
import json, os, subprocess, sys, time
from pathlib import Path
record, logfile, directory, *command = sys.argv[1:]
def started(pid):
    return subprocess.check_output(["ps", "-p", str(pid), "-o", "lstart="], text=True).strip()
path = Path(record)
if path.exists():
    previous = json.loads(path.read_text())
    try:
        if started(previous["pid"]) == previous["started"]:
            raise SystemExit("A previously started process is still alive but not ready; inspect its log before restarting.")
    except subprocess.CalledProcessError:
        pass
with open(logfile, "ab") as log, open(os.devnull, "rb") as stdin:
    child = subprocess.Popen(command, cwd=directory, stdin=stdin, stdout=log,
                             stderr=subprocess.STDOUT, start_new_session=True)
    time.sleep(0.2)
    if child.poll() is not None:
        raise SystemExit("Service exited during startup; inspect " + logfile)
    state = {"pid": child.pid, "started": started(child.pid),
             "directory": directory, "command": command}
    path.write_text(json.dumps(state, indent=2) + "\n")
    path.chmod(0o600)
PY
}

docker info >/dev/null 2>&1 || fail 'Docker is not ready. Open Docker Desktop, wait for it to start, then run this script again.'
compose() { docker compose --project-directory "$ROOT" --env-file "$ROOT/.env.local" -f "$ROOT/compose.yaml" "$@"; }
if port_busy 55433 && [[ -z $(compose ps -q postgres) ]]; then
  fail 'Port 55433 is occupied by another process. It was not stopped.'
fi
printf '%s\n' 'Checking PostgreSQL…'
compose up -d postgres >"$LOGS/postgres-start.log" 2>&1 || fail "PostgreSQL startup failed; see $LOGS/postgres-start.log."
postgres_ready() { compose exec -T postgres pg_isready -U jchatmind -d jchatmind >/dev/null 2>&1; }
wait_for PostgreSQL postgres_ready

if ollama_ready; then
  printf '%s\n' 'Ollama is already running; keeping the existing service.'
else
  port_busy 11434 && fail 'Port 11434 is occupied but is not a ready Ollama service. It was not stopped.'
  [[ -x "$JCHATMIND_OLLAMA_BIN" ]] || fail 'Ollama was not found. Install it or set JCHATMIND_OLLAMA_BIN.'
  launch ollama "$ROOT" env OLLAMA_HOST=127.0.0.1:11434 "$JCHATMIND_OLLAMA_BIN" serve
  wait_for Ollama ollama_ready
fi
if ! curl -fsS --max-time 5 http://127.0.0.1:11434/api/tags |
  python3 -c 'import json,sys; sys.exit(0 if any(m.get("name","").split(":")[0]=="bge-m3" for m in json.load(sys.stdin)["models"]) else 1)'; then
  [[ -x "$JCHATMIND_OLLAMA_BIN" ]] || fail 'The bge-m3 model is missing; run ollama pull bge-m3.'
  printf '%s\n' 'Downloading bge-m3 for local knowledge retrieval; this can take several minutes…'
  OLLAMA_HOST=127.0.0.1:11434 "$JCHATMIND_OLLAMA_BIN" pull bge-m3 >"$LOGS/embedding-model.log" 2>&1 || fail "Model download failed; see $LOGS/embedding-model.log."
fi

if backend_ready; then
  printf '%s\n' 'JChatMind backend is already running; keeping the existing service.'
else
  port_busy 8080 && fail 'Port 8080 is occupied but the JChatMind API is not ready. It was not stopped.'
  [[ -x "$JCHATMIND_JAVA_HOME/bin/java" ]] || fail 'Java was not found. Set JCHATMIND_JAVA_HOME to your JDK 21 directory.'
  if [[ ! -f "$ROOT/jchatmind/target/jchatmind-0.0.1-SNAPSHOT.jar" ]]; then
    printf '%s\n' 'Building the backend…'
    (cd "$ROOT/jchatmind" && JAVA_HOME="$JCHATMIND_JAVA_HOME" ./mvnw -q -DskipTests package) >"$LOGS/backend-build.log" 2>&1 || fail "Backend build failed; see $LOGS/backend-build.log."
  fi
  launch backend "$ROOT/jchatmind" "$JCHATMIND_JAVA_HOME/bin/java" -jar "$ROOT/jchatmind/target/jchatmind-0.0.1-SNAPSHOT.jar" --spring.profiles.active=local "--spring.config.additional-location=optional:file:$LOCAL/config/" --server.address=127.0.0.1 --server.port=8080
  wait_for Backend backend_ready
fi

if frontend_ready; then
  printf '%s\n' 'JChatMind UI is already running; keeping the existing service.'
else
  port_busy 5174 && fail 'Port 5174 is occupied by another service. It was not stopped.'
  command -v node >/dev/null || fail 'Node.js is missing; use Node 22.17 or a compatible newer version.'
  command -v npm >/dev/null || fail 'npm is missing.'
  if [[ ! -f "$ROOT/ui/node_modules/vite/bin/vite.js" ]]; then
    printf '%s\n' 'Installing frontend dependencies…'
    (cd "$ROOT/ui" && npm ci) >"$LOGS/frontend-install.log" 2>&1 || fail "Frontend install failed; see $LOGS/frontend-install.log."
  fi
  # This is npm run dev's Vite entrypoint without an extra npm wrapper process.
  launch frontend "$ROOT/ui" "$(command -v node)" "$ROOT/ui/node_modules/vite/bin/vite.js" --host 127.0.0.1 --port 5174 --strictPort
  wait_for Frontend frontend_ready
fi

printf '\n%s\n' 'Ready: http://127.0.0.1:5174' 'Backend: http://127.0.0.1:8080/health' "Logs: $LOGS" 'Demo content: python3 scripts/seed-demo.py (optional; see LOCAL-SETUP.md).'
