# JChatMind local setup

This checkout runs the Java/Spring AI backend, React UI, PostgreSQL with pgvector, and local Ollama embeddings. Chat uses the configured DeepSeek API. No cloud deployment is required.

## Open and start

Open Docker Desktop and wait until its engine is ready. In a terminal:

```bash
cd '/Users/wanghongxiang/Documents/管家 2/jchatmind-local'
bash scripts/start-local.sh
```

Open **http://127.0.0.1:5174**. The script reuses services already running correctly; it refuses to replace an unrelated process occupying a required port.

| Component | Local address | Storage/configuration |
| --- | --- | --- |
| React UI | `http://127.0.0.1:5174` | `ui/` |
| Spring Boot API | `http://127.0.0.1:8080` | `.local/config/application-local.yaml` |
| PostgreSQL + pgvector | `127.0.0.1:55433` | Independent Compose volume `jchatmind-local_postgres-data` |
| Ollama | `http://127.0.0.1:11434` | Existing user model storage; model `bge-m3` |

The UI currently expects backend port 8080. Keep these ports unless both API and SSE client configuration are updated.

## Local requirements and configuration

- Docker Desktop, Python 3, Node.js 22.17 (the verified version), npm, and JDK 21.
- Default JDK: `/Library/Java/JavaVirtualMachines/temurin-21.jdk/Contents/Home`. Override with `JCHATMIND_JAVA_HOME` if needed.
- Default Ollama executable: `/Applications/Ollama.app/Contents/Resources/ollama`. Override with `JCHATMIND_OLLAMA_BIN` if needed.
- `.env.local` supplies the Compose PostgreSQL password. `.local/config/application-local.yaml` supplies the matching database connection and DeepSeek credentials. Both are ignored by Git and already configured on this machine; the scripts do not print their contents. A new machine needs its own local copies.
- `compose.yaml` starts an isolated PostgreSQL service and runs `infra/init.sql` only when its data volume is first created. Restarting preserves agents, chats, knowledge bases, and vectors.
- `bge-m3` is already downloaded. If missing, `start-local.sh` downloads it through Ollama. Embeddings run locally; chat requests use DeepSeek.
- `start-local.sh` builds a missing backend JAR and installs missing UI dependencies. It **does not rebuild an existing JAR** after Java source changes; use the rebuild commands below.

## Demo content

The existing `JChatMind Demo` agent uses DeepSeek and the local demo knowledge base. It has no optional email or SQL tools enabled.

To create/reuse this content after startup:

```bash
python3 scripts/seed-demo.py
```

The script reads `docs/demo-knowledge.md`, creates missing demo records, and writes their IDs to `.local/demo.json`. It does not erase existing conversations. It reuses an existing demo knowledge base/agent rather than overwriting their configuration.

Try a fresh chat with `JChatMind Demo`:

1. `Use your date tool to tell me today's date.`
2. `Search my configured knowledge base for the JChatMind demo verification code and quote the exact code.`

The demo knowledge file currently produces three chunks with 1024-dimensional embeddings. Upload success alone is not proof of indexing: the original upload code can log embedding failures without failing the upload response. A successful answer containing the document's unique fact verifies the retrieval path.

Existing chat pages keep an SSE connection open. The original first-message flow submits before opening the chat page, so a connection race is still possible; the initial browser chat passed this run. For direct API testing, keep `GET /sse/connect/{sessionId}` connected before calling `POST /api/chat-messages`; otherwise the original backend rejects stream delivery.

## Stop and restart

```bash
bash scripts/stop-local.sh
bash scripts/start-local.sh
```

`stop-local.sh` stops only frontend/backend/Ollama process groups created by `start-local.sh`, identified by PID and process start time in `.local/pids/`. Services started in another terminal or by an app are left running. It does not stop Docker Desktop, delete files or volumes, or stop the PostgreSQL container. Logs remain in `.local/logs/`.

To intentionally stop only this project's database while retaining data:

```bash
docker compose --env-file .env.local stop postgres
```

The script does not force-kill a service that is slow to stop. It preserves its PID record and reports the remaining process.

## Rebuild after source changes

First stop the backend you started; if it was started outside these scripts, stop it in its original terminal. Then:

```bash
cd '/Users/wanghongxiang/Documents/管家 2/jchatmind-local/jchatmind'
JAVA_HOME=/Library/Java/JavaVirtualMachines/temurin-21.jdk/Contents/Home ./mvnw -q -DskipTests package
cd ../ui
npm ci
npm run build
cd ..
bash scripts/start-local.sh
```

The backend package and frontend production build passed in the local setup. `-DskipTests` means the Maven command verifies packaging, not test execution. The startup and stop scripts passed a real stop/start check. Browser checks verified a DeepSeek date-tool response, retrieval of BLUE-ORCHID-482 from the uploaded Markdown, and persisted messages after restarting the backend.

## Current demonstration limits

- DeepSeek and local RAG are configured; GLM and email have not been configured/tested for this local setup.
- City and weather tools return fixed example data. The date tool reads the actual machine date.
- Keep initial demonstrations sequential. This is the restored local project, with some original agent/session limitations still present.
- Logs: `.local/logs/backend.log`, `frontend.log`, `ollama.log`, and `postgres-start.log` for services launched by the script. Earlier manually started services may log elsewhere.
