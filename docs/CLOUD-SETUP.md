# JChatMind cloud demo

This deploys the original React + Spring Boot / Spring AI application. It keeps PostgreSQL / pgvector and Ollama `bge-m3` on the server; DeepSeek remains the external chat model. The original application at `/` is available to the owner through browser Basic Auth over HTTPS, including Agent/knowledge-base management, document upload, chat history and SSE chat. The public entry point is `/demo`. Guests receive an isolated, expiring session and cannot browse existing chats or edit agents/documents.

```text
Portfolio iframe → HTTPS /demo → Caddy → Nginx → React
                                          └─ /api/demo/* → Spring Boot
                                                          ├─ DeepSeek chat
                                                          ├─ Ollama embeddings
                                                          └─ PostgreSQL + pgvector
```

## Before deployment

- A Linux VM with Docker Engine and Docker Compose v2. The script uses `docker compose up --wait` and multiple `--env-file` flags.
- A domain/subdomain pointed at the VM. HTTPS is required to embed this demo in the HTTPS Portfolio; plain HTTP/IP alone is insufficient.
- Ports 80 and 443 reachable for Caddy HTTPS; SSH access should be restricted to the owner's access method. PostgreSQL, Ollama and Java have **no published host ports**.
- A DeepSeek API key supplied privately at runtime.
- Initial capacity estimate: 2 CPU cores, 4 GB RAM and 20 GB free disk for a low-concurrency demonstration. This is a starting estimate, not a measured capacity guarantee; benchmark the selected VM. Building Java/Node images and loading the embedding model can temporarily need more memory/disk. Build images on a larger machine or add appropriate swap if the chosen small VM cannot build them.
- Hosting, domain, storage/backups, egress and model usage are separate charges. No provider account, purchase or spending commitment is created by these files. Configure the provider's budget/usage alerts before sharing the live URL. Guest limits reduce abuse but are not a guarantee of a currency-denominated budget cap.

## Configure and start

Run all commands from this repository root on the VM. The cloud stack uses its own Compose project and named volumes; the existing `compose.yaml` local setup is unchanged.

```bash
bash scripts/cloud-init.sh
```

Edit `.local/cloud/secrets.env` privately. `cloud-init.sh` creates separate random database, internal admin API and guest-signing secrets and never replaces an existing file. It also creates `.local/cloud/admin-login.env` with the owner's browser username/password, and a separate `admin.htpasswd` hash mounted read-only into Nginx. Rerun init when upgrading the earlier guest-only setup: it adds missing login files without changing existing credentials. `.local/` is ignored by Git and excluded from Docker's build context. Open the login file privately to obtain the browser credentials; the scripts never print them. Set:

| Value | Purpose |
| --- | --- |
| `DEEPSEEK_API_KEY` | Server-side chat-model credential |
| `POSTGRES_PASSWORD` | Cloud PostgreSQL password; generated automatically |
| `JCHATMIND_ADMIN_SECRET` | Admin API header; generated automatically, at least 32 characters |
| `JCHATMIND_DEMO_SIGNING_SECRET` | Guest-token signing; generated separately, at least 32 characters |
| `DEMO_DOMAIN` | Hostname only, e.g. `demo.example.com` |
| `ACME_EMAIL` | Email for HTTPS certificate notices |
| `PORTFOLIO_ORIGIN` | Exact permitted embedding origin; defaults to the existing Portfolio |
| `CLOUD_HTTP_PORT` | Loopback-only verification port, default `8082` |

Use plain single-line values in this file; the scripts do not execute it as shell code. The internal admin secret must use 32–128 URL-safe characters (`A–Z`, `a–z`, `0–9`, `_`, `-`); the generated hexadecimal secret already meets this requirement. Keep the secret and browser-login files at `600`. Their parent directory is `700`; only the password-hash file is `644` so Nginx's unprivileged worker can read the bind mount. It is mounted outside the web root. Never place these values in Vite environment variables or the frontend bundle. The initialization script requires OpenSSL to create the password hash.

```bash
bash scripts/cloud-start.sh
bash scripts/cloud-verify.sh
bash scripts/cloud-verify.sh --admin
bash scripts/cloud-https.sh
bash scripts/cloud-verify.sh https://demo.example.com
bash scripts/cloud-verify.sh https://demo.example.com --admin
```

`cloud-start.sh` starts PostgreSQL and Ollama, downloads `bge-m3`, builds the API/UI, imports the original fictional OrbitDesk handbook through the authenticated admin API, then recreates the API with the returned Agent/KB IDs. The public demo returns `503` until these IDs have been configured. The script checks that all four handbook sections actually have vectors; an upload response alone does not prove indexing succeeded.

Seed state lives in `.local/cloud/seed.json`; non-secret returned IDs live in `.local/cloud/demo.env`. Rerunning the seed reuses the named KB, document and Agent. It updates only the dedicated public-demo Agent configuration. It does not delete or copy existing local conversations. A changed source handbook requires a reviewed re-index rather than silently claiming old indexed content is current.

The default web port binds only `127.0.0.1`. `cloud-https.sh` enables the separate Caddy profile after checking the configured domain/email. Caddy's data volumes preserve certificate state across restarts. Inspect certificate issuance if the HTTPS check fails:

```bash
bash scripts/cloud-compose.sh logs --tail=80 caddy
bash scripts/cloud-compose.sh ps
```

## Release verification and Portfolio embedding

The smoke script verifies the React route, embedding policy, anonymous admin-route rejection, invalid guest-token rejection, and creation/readback of an empty guest session. With `--admin`, it additionally checks the original owner UI, Agent/KB/document/history APIs and SSE initialization. It only sends browser credentials to loopback or the exact configured HTTPS `DEMO_DOMAIN`, and refuses redirects. It does **not** make a paid model call.

Nginx verifies Basic Auth before injecting `X-JChatMind-Admin` into original `/api/` and `/sse/` upstream requests; the browser never receives the internal secret. The three exact guest API locations explicitly remove a caller-supplied admin header and preserve their guest Bearer token. Public `/demo` and assets remain usable without a browser-login prompt. Admin requests with an unrelated `Origin` are rejected. Java retains its own header boundary, and its port is not published. Visit the original UI in its own HTTPS tab; use `/demo` for the public Portfolio iframe.

To test the real proxy rules against an inert upstream using generated credentials, run `python3 scripts/test-cloud-proxy.py` with Docker available and the cached `jchatmind-cloud-web:local` image. This isolated test also checks uploads/SSE proxy paths, forged headers, encoded path variants and idempotent initialization. It neither accesses the real database nor calls a model.

Before sharing the URL, open `https://demo.example.com/demo` and send one real question:

> We have 8 people and need CSV exports and Slack alerts. Which OrbitDesk plan fits, and what is the monthly price?

Expected answer: Team plan, USD 18/user/month, USD 144/month before taxes, grounded in the handbook. Then ask a follow-up about 12 people (USD 216), a trial starting today (real date tool + 14 calendar days), and SAML SSO (not specified). These checks exercise the real original RAG/model path and consume model usage. Open a separate private browser session to verify that one visitor cannot see the other's conversation.

Embed the verified HTTPS `/demo` URL in the Portfolio iframe. The Nginx `frame-ancestors` policy permits only the configured Portfolio origin and the demo's own origin. It deliberately does not send `X-Frame-Options: SAMEORIGIN`, which would block the Portfolio. Keep the same-origin `/api` proxy; never embed `127.0.0.1:5174` or pass admin credentials to the browser.

## Updates, persistence and recovery

```bash
# Build/start changed code while retaining cloud database/documents/model volumes.
bash scripts/cloud-compose.sh up -d --build --wait api web

# Re-run seed after a new empty database, then load the real returned IDs.
bash scripts/cloud-seed.sh
bash scripts/cloud-compose.sh up -d --wait api web

# Stop containers; named data volumes remain.
bash scripts/cloud-compose.sh --profile https down
```

Do not use `down -v` on a deployed instance unless intentionally deleting its data. The database, original uploaded handbook files, embedding model and HTTPS state live in separate named volumes. Keep `.local/cloud/` securely alongside backups: it holds the database password, signing/admin secrets and actual demo IDs. Rotating the signing secret invalidates existing guest tokens. Changing the PostgreSQL environment password alone does not change the password inside an existing database volume.

Container log files rotate at 10 MB × 3 per service. Back up PostgreSQL and the uploaded-documents volume before changes that alter stored data; a VM snapshot alone is not a tested restore procedure. Image tags are pinned to explicit major/minor releases where available, but tags can move; record deployed image digests if exact rebuild provenance is required.

References: [Ollama Docker image](https://ollama.com/blog/ollama-is-now-available-as-an-official-docker-image), [bge-m3 model](https://ollama.com/library/bge-m3), [Caddy reverse proxy](https://caddyserver.com/docs/caddyfile/directives/reverse_proxy).
