#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
command -v python3 >/dev/null || { printf '%s\n' 'python3 is required.' >&2; exit 1; }

python3 - "$ROOT/.local/pids" <<'PY'
import json, os, signal, subprocess, sys, time
from pathlib import Path

root = Path(sys.argv[1])
failed = False
def started(pid):
    try:
        return subprocess.check_output(["ps", "-p", str(pid), "-o", "lstart="], text=True).strip()
    except subprocess.CalledProcessError:
        return None

for name in ("frontend", "backend", "ollama"):
    record = root / (name + ".json")
    if not record.exists():
        print(name + ": not started by start-local; left unchanged.")
        continue
    try:
        state = json.loads(record.read_text())
        pid = state["pid"]
        if not isinstance(pid, int) or pid <= 1:
            raise ValueError("invalid PID")
        current = started(pid)
        if current is None:
            record.unlink()
            print(name + ": already stopped.")
            continue
        if current != state["started"] or os.getpgid(pid) != pid:
            print(name + ": ownership no longer matches; process left unchanged.")
            failed = True
            continue
        # The dedicated group includes only this service and its own workers.
        os.killpg(pid, signal.SIGTERM)
        # Spring Boot may need 30 seconds to drain active SSE requests.
        for _ in range(180):
            if started(pid) != state["started"]:
                break
            time.sleep(0.25)
        else:
            print(name + ": still stopping; kept its PID record. Run this script again later.")
            failed = True
            continue
        record.unlink()
        print(name + ": stopped.")
    except ProcessLookupError:
        record.unlink(missing_ok=True)
        print(name + ": already stopped.")
    except (OSError, ValueError, KeyError) as error:
        print(name + ": not stopped (" + str(error) + ").")
        failed = True

print("PostgreSQL data, Docker Desktop, and services started elsewhere were left unchanged.")
sys.exit(1 if failed else 0)
PY
