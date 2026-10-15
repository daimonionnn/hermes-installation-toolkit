# Running Multiple Hermes Instances on One Machine (Profiles)

Hermes has built-in support for several independent agents on a single bare-metal install — no Docker, no second install. The feature is called **profiles**, and `hermes profile --help` describes it as *"multiple isolated Hermes instances"*.

Each profile has its own config, API keys, bot tokens, skills, sessions, memory, cron jobs and gateway service. They share the installed code, so you update once.

This is the bare-metal counterpart to [Install a Secondary Hermes Agent in Docker](install-secondary-hermes-docker.md). See [Profiles or Docker?](#profiles-or-docker) for which to pick, and [Migrating a Docker Instance into a Profile](#migrating-a-docker-instance-into-a-profile) if you already run the Docker one.

---

## Table of Contents

- [How Profiles Are Laid Out](#how-profiles-are-laid-out)
- [1. Create a Profile](#1-create-a-profile)
- [2. Run It](#2-run-it)
- [3. Give It a Gateway Service](#3-give-it-a-gateway-service)
- [4. Autostart, or Manual Control](#4-autostart-or-manual-control)
- [What Must Be Unique Per Profile](#what-must-be-unique-per-profile)
- [What All Profiles Share](#what-all-profiles-share)
- [Migrating a Docker Instance into a Profile](#migrating-a-docker-instance-into-a-profile)
- [Profiles or Docker?](#profiles-or-docker)
- [Troubleshooting](#troubleshooting)

---

## How Profiles Are Laid Out

| Path | What it is |
|---|---|
| `~/.hermes/` | The `default` profile — your original install |
| `~/.hermes/profiles/<name>/` | A named profile's data directory |
| `~/.local/bin/<name>` | Wrapper script that runs Hermes with that profile |
| `~/.hermes/active_profile` | Sticky default set by `hermes profile use` |
| `~/.hermes/hermes-agent/` | The code and venv — **shared by every profile** |

A profile directory holds the same files as `~/.hermes`: `config.yaml`, `.env`, `SOUL.md`, `skills/`, `sessions/`, `memories/`, `cron/`, `state.db`, `logs/`.

Under the hood a profile is just a different `HERMES_HOME`, which is why all three of these are equivalent:

```bash
secondary chat                                             # wrapper script
hermes -p secondary chat                                   # profile flag
HERMES_HOME=~/.hermes/profiles/secondary hermes chat       # the mechanism itself
```

---

## 1. Create a Profile

```bash
hermes profile create research
```

Useful flags:

| Flag | Effect |
|---|---|
| `--clone` | Copy `config.yaml`, `.env`, `SOUL.md` and skills from the active profile |
| `--clone-all` | Full copy of the active profile, minus per-profile history |
| `--clone-from <profile>` | Clone from a specific profile instead of the active one |
| `--description "..."` | Role description; the kanban decomposer routes tasks by it |
| `--no-skills` | Empty profile, and opt out of bundled-skill sync |
| `--no-alias` | Skip the `~/.local/bin/<name>` wrapper |

Without `--clone` the profile starts blank and needs its own `research setup` (model, provider, keys). With `--clone` it inherits your working model config and you only change what differs — most often the bot token.

Check what you have at any time:

```bash
hermes profile list
```

```
 Profile          Model                        Gateway      Alias
 ◆default        Qwen3.8-Flash-Next           running      —
  secondary      auto                         running      secondary
```

---

## 2. Run It

```bash
research chat                      # interactive
research chat -q "say ok"          # one-shot, good for a smoke test
research setup model               # change its model only
research config edit               # edit that profile's config.yaml
```

To make a profile the default for bare `hermes` commands:

```bash
hermes profile use research        # sticky
hermes profile use default         # back
```

> Sessions, memory and skills never cross profiles. `research` cannot resume a `default` session, which is the point.

---

## 3. Give It a Gateway Service

Each profile runs its own gateway (messaging platforms + cron). `hermes gateway start` **only starts an already installed systemd service**, so a new profile needs `install` first:

```bash
research gateway install --start-now --no-start-on-login
```

That writes `~/.config/systemd/user/hermes-gateway-research.service` with `HERMES_HOME` pointing at the profile. The `default` profile's unit stays `hermes-gateway.service`.

Day-to-day control, either through Hermes or systemd directly:

```bash
research gateway status            # start | stop | restart | status
hermes gateway list                # every profile's gateway and PID

systemctl --user status hermes-gateway-research
journalctl --user -u hermes-gateway-research -f
```

`hermes gateway list` is the quickest overview:

```
Gateways:
  ✓ default (current)        — PID 8678
  ✓ secondary                — PID 75491
```

To run a gateway in the foreground instead (no service at all), use `research gateway run`.

---

## 4. Autostart, or Manual Control

`install` decides boot behaviour, and you can change it later:

```bash
research gateway install --start-on-login       # start at boot/login
research gateway install --no-start-on-login    # manual only
```

Equivalently, with systemd:

```bash
systemctl --user enable  hermes-gateway-research    # autostart on
systemctl --user disable hermes-gateway-research    # autostart off, unit kept
systemctl --user is-enabled hermes-gateway-research
```

`disable` leaves the service installed, so `research gateway start` still works — it just will not come up by itself. Hermes also enables **systemd linger** for your user, so an enabled gateway survives logout and starts without anyone logging in.

---

## What Must Be Unique Per Profile

Two profiles are isolated in their data, not in the ports and accounts they reach for. These are on you:

| Thing | Why | Where |
|---|---|---|
| **Bot token** per platform | Two gateways polling one Telegram bot steal each other's updates | `TELEGRAM_BOT_TOKEN` (and the Discord/Slack equivalents) in that profile's `.env` |
| **API server port** | Hermes' own OpenAI-compatible endpoint defaults to `8642` | `API_SERVER_PORT` in `.env`, e.g. `8645` |
| **Webhook ports** | Same reason, if you use webhook mode | `TELEGRAM_WEBHOOK_PORT` etc. |
| **Dashboard port** | Only if you enable the dashboard in more than one profile | `hermes dashboard --help` |

Everything else — the LLM endpoint, Firecrawl, Chrome CDP on `9222` — is a read-only client connection and can be shared by all profiles.

> **The API server is not the LLM.** `API_SERVER_*` exposes *the agent* as an OpenAI-compatible model so frontends like Open WebUI can talk to it. It is off unless `API_SERVER_ENABLED=true`.

---

## What All Profiles Share

- **The code and the venv.** `hermes update` updates every profile at once, and all of them run the same version. That is the big practical difference from Docker, where each instance has its own image.
- **The kanban board.** It is designed as a multi-profile collaboration board. One gateway holds the dispatcher lock (`~/.hermes/kanban/.dispatcher.lock`) and the others log `this gateway will NOT dispatch` — expected, not an error.
- **The host.** Every profile runs as your user, with your files, your `sudo`, your GPU, your Docker socket. Profiles separate data and configuration, **not privileges**. If you need an agent that cannot reach your home directory, use Docker instead.
- **Hardware.** Concurrent agents share one GPU and one LLM server. A single local model serving several busy gateways is usually the first bottleneck.

---

## Migrating a Docker Instance into a Profile

If you already run the Docker secondary agent and want it on bare metal, this toolkit ships a helper:

```bash
bash migrate_docker_hermes_to_profile.sh secondary
```

It is read-only towards the container's data directory, so the Docker instance stays usable as a fallback. The script:

1. Creates the profile (or reuses an existing directory) and registers it.
2. Copies config, `.env`, `SOUL.md`, skills, sessions, memories, kanban, cron, hooks and workspace into it.
3. **Skips** `bin/`, `lazy-packages/`, `.local/` and `home/` — binaries and Python packages built for the image — plus caches, logs and gateway runtime locks.
4. Rewrites `host.docker.internal` and `172.17.0.1` to `127.0.0.1` in `config.yaml` and `.env` (backups: `*.bak-premigration`). On bare metal the host *is* loopback.
5. Copies the `tirith` command scanner from the main install, since the container's build was excluded.
6. Reports what needs a decision: unreadable files, whether the bot token collides with the main profile, and whether the API server port needs changing.

Options:

```bash
DRY_RUN=1 bash migrate_docker_hermes_to_profile.sh secondary     # list, don't copy
SRC_DIR=~/.hermes-research bash migrate_docker_hermes_to_profile.sh research
```

Then test and start it:

```bash
secondary chat -q "say ok"
secondary gateway install --start-now --no-start-on-login
```

Two things to know afterwards:

- **A handful of files cannot be copied.** Anything the container wrote as its own uid (`10000`) is unreadable to your user: cache files, `skills/.usage.json`, `.bundled_manifest`, and the odd old session. Hermes regenerates all of it. Use `sudo rsync` afterwards if you really want those sessions.
- **The profile and the container share one bot token**, because the token was copied. Never run both gateways at once; stop one before starting the other:

```bash
secondary gateway stop
bash docker/hermes_docker_secondary.sh start
```

The Docker data directory is not a profile — `hermes profile list` will not show `~/.hermes-secondary`, and the two copies drift apart from the moment you migrate.

---

## Profiles or Docker?

| | Profiles (bare metal) | Docker instance |
|---|---|---|
| Isolation of data | Yes | Yes |
| Isolation of privileges | **No** — full access as your user | Yes, only what you mount or publish |
| Version independence | No — one shared install | Yes, per image |
| Setup effort | One command | Compose file, data dir, port mapping |
| Reaching host services | Plain `127.0.0.1` | `host.docker.internal`, published ports only |
| GPU access | Direct | Needs `nvidia-container-toolkit` and `gpus: all` |
| Survives a bad update | No | Yes — pin the old image |

Rough rule: use **profiles** for several agents you trust equally (different bots, different roles, different models). Use **Docker** when the second agent should be sandboxed, or when you want a version you can pin and roll back.

---

## Troubleshooting

### ❌ `gateway service is not installed`

`gateway start` only starts an existing systemd unit. A new profile has none yet:

```bash
research gateway install --start-now --no-start-on-login
```

### ❌ Telegram messages land in the wrong agent, or stop arriving

Two gateways are polling the same bot. Compare tokens without printing them:

```bash
for f in ~/.hermes/.env ~/.hermes/profiles/*/.env; do
  printf '%-45s %s\n' "$f" "$(grep -m1 '^TELEGRAM_BOT_TOKEN=' "$f" | cut -d= -f2- | cut -d: -f1)"
done
```

The part before the colon is the bot id and is not secret. Same id in two running profiles means you need a second bot from @BotFather.

### ⚠ `tirith security scanner enabled but not available`

The profile has no `tirith` binary on its PATH. Copy it from the main install:

```bash
mkdir -p ~/.hermes/profiles/research/bin
cp ~/.hermes/bin/tirith ~/.hermes/profiles/research/bin/
```

Or set `tirith_enabled: false` under `security:` in that profile's `config.yaml`.

### ❌ Port already in use after enabling the API server

`8642` belongs to whichever profile claimed it first. Give the others their own:

```dotenv
API_SERVER_ENABLED=true
API_SERVER_HOST=127.0.0.1
API_SERVER_PORT=8645
API_SERVER_MODEL_NAME=hermes-research
```

### A profile is missing bundled skills after `hermes update`

Profiles created with `--no-skills` carry a `.no-bundled-skills` marker and are skipped by skill sync. Delete the marker to opt back in:

```bash
rm ~/.hermes/profiles/research/.no-bundled-skills
```

### Starting over

```bash
hermes profile delete research          # removes the data dir and the wrapper
```

This deletes that profile's sessions, memory and keys. Export first if you might want it back:

```bash
hermes profile export research
```

---

## Related Guides

- [Install a Secondary Hermes Agent in Docker](install-secondary-hermes-docker.md) — the sandboxed alternative
- [Install Chrome DevTools MCP Server](install-mcp-chrome-dev-tools.md) — per-profile `mcp_servers` entries work the same way
- [Browser Automation: CDP Explained](browser-cdp-explained.md) — one always-on Chrome can serve every profile
