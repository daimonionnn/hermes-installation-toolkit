# Install a Secondary Hermes Agent in Docker

This guide sets up a **second Hermes Agent** in Docker while keeping your existing bare-metal Hermes install untouched.

The important rule is isolation:

- Bare-metal Hermes keeps using `~/.hermes/`
- Docker Hermes uses a separate host directory: `~/.hermes-secondary/`
- Bare-metal API server can keep port `8642`
- Docker Hermes publishes container port `8642` on host port `8643`

Never run two Hermes gateways against the same data directory at the same time.

---

## Files Added by This Toolkit

| File | Purpose |
|---|---|
| `docker/hermes_docker_secondary.sh` | Helper script for setup, start, logs, shell, stop |
| `docker/docker-compose.hermes-secondary.yml` | Persistent Docker Compose service for the secondary agent |

---

## Prerequisites

- Docker installed and running
- Docker Compose v2 available as `docker compose` (override with `COMPOSE_CLI=docker-compose` for the legacy v1 binary)
- Your local LLM/API provider reachable from the container

If you use LM Studio, Ollama, or another host-side OpenAI-compatible server, do **not** configure the Docker agent with `http://127.0.0.1:...`. Inside the container, `127.0.0.1` means the container itself.

Use this instead:

```text
http://host.docker.internal:1234/v1
```

Replace `1234` with your host LLM server port. Also ensure the host LLM server listens on an address reachable from Docker, such as `0.0.0.0` or your LAN interface.

---

## 1. Run the One-Time Docker Setup Wizard

From this repository:

```bash
bash docker/hermes_docker_secondary.sh setup
```

During model/provider setup:

- Use a different bot token than your bare-metal Hermes if connecting Telegram/Discord/Slack/etc.
- For a host-side local OpenAI-compatible server, use `http://host.docker.internal:<port>/v1`.
- The Docker agent writes its config, secrets, memory, sessions, logs, and skills to `~/.hermes-secondary/`.

---

## 2. Start the Secondary Gateway

```bash
# First time only — run setup before starting
bash docker/hermes_docker_secondary.sh setup   # one-time config wizard
bash docker/hermes_docker_secondary.sh start   # start the gateway
```

On subsequent runs, just start directly:

```bash
bash docker/hermes_docker_secondary.sh start
```

Check status:

```bash
bash docker/hermes_docker_secondary.sh status
```

Follow logs:

```bash
bash docker/hermes_docker_secondary.sh logs
```

---

## 3. Optional: Enable the Docker Agent API Server

If you want OpenAI-compatible API access to the Docker Hermes instance, edit:

```bash
nano ~/.hermes-secondary/.env
```

Add or update:

```dotenv
API_SERVER_ENABLED=true
API_SERVER_HOST=0.0.0.0
API_SERVER_PORT=8642
API_SERVER_KEY=change-this-to-a-long-random-secret
API_SERVER_MODEL_NAME=hermes-secondary
```

Restart the container:

```bash
bash docker/hermes_docker_secondary.sh restart
```

The Docker agent API will be available on the host at:

```text
http://localhost:8643/v1
```

Port `8643` is used on the host to avoid clashing with a bare-metal Hermes API server on `8642`.

---

## 4. Start Chatting

The secondary agent runs as a gateway. There are three ways to chat with it:

### Option A — Messaging platform (Telegram, Discord, Slack, etc.)

If you configured a bot token during setup, just open the chat in that platform. It is a separate bot account, fully isolated from your bare-metal Hermes.

### Option B — Interactive CLI (quickest, no extra config)

```bash
bash docker/hermes_docker_secondary.sh shell
hermes
```

The `shell` command now opens a container shell with Hermes already on PATH.

### Option C — API server (Open WebUI, LobeChat, curl, etc.)

1. Enable the API server in `~/.hermes-secondary/.env` (if not already done in Step 3 above)
2. Restart the container:

```bash
bash docker/hermes_docker_secondary.sh restart
```

3. Test with curl:

```bash
curl http://localhost:8643/v1/chat/completions \
  -H "Authorization: Bearer YOUR_API_SERVER_KEY" \
  -H "Content-Type: application/json" \
  -d '{"model":"hermes-secondary","messages":[{"role":"user","content":"Hello!"}]}'
```

Or point any OpenAI-compatible frontend (Open WebUI, LobeChat, ChatBox, etc.) at:

```text
Base URL : http://localhost:8643/v1
API Key  : YOUR_API_SERVER_KEY
```

---

## Common Operations

```bash
# Stop the Docker agent
bash docker/hermes_docker_secondary.sh stop

# Restart it
bash docker/hermes_docker_secondary.sh restart

# Open a shell in the running container
bash docker/hermes_docker_secondary.sh shell
# then start chat
hermes

# Update to the latest image
bash docker/hermes_docker_secondary.sh pull
bash docker/hermes_docker_secondary.sh start
```

> **`restart` does not update the image.** It restarts the existing container, which keeps running the image it was created from. Only `pull` followed by `start` recreates the container on the new image. Check which version is actually running with `docker exec hermes-secondary /opt/hermes/.venv/bin/hermes --version` — an old image can lag far behind your bare-metal install and behave differently (for example in provider fallback handling).

---

## Use a Different Data Directory or Port

```bash
HERMES_SECONDARY_DATA_DIR=$HOME/.hermes-research \
HERMES_SECONDARY_API_PORT=8644 \
bash docker/hermes_docker_secondary.sh setup

HERMES_SECONDARY_DATA_DIR=$HOME/.hermes-research \
HERMES_SECONDARY_API_PORT=8644 \
bash docker/hermes_docker_secondary.sh start
```

---

## Connecting to a Local LLM (vLLM, Ollama, LM Studio)

Docker containers cannot reach `localhost` or `127.0.0.1` on the host — those addresses resolve to the container itself. Use `host.docker.internal` instead, which the Compose file already maps to the host via `extra_hosts`.

### vLLM example (port 8000)

During `hermes setup` inside the container, set the API base URL to:

```text
http://host.docker.internal:8000/v1
```

Or edit `~/.hermes-secondary/config.yaml` directly and restart:

```yaml
model:
  default: Qwen3.6-27B-FP8   # must match --served-model-name in your vLLM command
  provider: custom
  base_url: http://host.docker.internal:8000/v1
```

```bash
bash docker/hermes_docker_secondary.sh restart
```

> **Requirement:** vLLM must be started with `--host 0.0.0.0` (not `127.0.0.1`) so Docker's bridge network can reach it. The example command in the tested environment already does this.

To verify connectivity from inside Docker before configuring Hermes:

```bash
docker run --rm --add-host=host.docker.internal:host-gateway curlimages/curl:latest \
  curl -sf http://host.docker.internal:8000/v1/models
```

A JSON response listing your model confirms the container can reach vLLM.

---

## Safety Notes

- Do not mount `~/.hermes` into the Docker container if your bare-metal gateway is running.
- Do not reuse the same Telegram/Discord/Slack bot token in both agents unless you intentionally want conflicts.
- If exposing the API server beyond localhost, keep `API_SERVER_KEY` strong and restrict network access with a firewall or reverse proxy.
- The Compose file includes `host.docker.internal` support so the container can reach host services.
