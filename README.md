# 🐉 Hermes Installation Toolkit

A practical guide and set of scripts for installing **Hermes Agent** — a fully self-hosted, offline-capable AI agent — on Linux systems. Includes setup for local LLM inference, browser automation, web search backends, Chrome DevTools MCP integration, and migration from OpenClaw.

[![Hermes Agent](https://img.shields.io/badge/Hermes-v0.21.2-blue)](https://hermes-agent.nousresearch.com/) [![Platform](https://img.shields.io/badge/Platform-Linux-green)](https://ubuntu.com/) [![License](https://img.shields.io/badge/License-MIT-yellow)](LICENSE)

> **Official docs:** <https://hermes-agent.nousresearch.com/docs>

---

## 📋 Tested Environment

| Component | Spec |
|---|---|
| OS | Ubuntu 24.04 LTS / 25.04 |
| CPU | AMD Ryzen 7 5700G (or similar) |
| RAM | 64 GB |
| GPU | NVIDIA GeForce RTX 5090 32 GB VRAM |
| LLM | Qwen 3.6 27B Q4\_M via LM Studio (local, OpenAI-compatible API) |

---

## 🚀 Quick Start

```bash
# 1. Install Hermes Agent
curl -fsSL https://hermes-agent.nousresearch.com/install.sh | bash

# 2. Run the setup wizard
hermes setup

# 3. Start chatting or launch the gateway
hermes
hermes gateway start
```

> **Video walkthrough:** [YouTube — Hermes AI Agent Setup](https://www.youtube.com/watch?v=THA8Fov44QY)

### ✅ Optional (but recommended) post-install steps

#### Step A — Self-hosted Firecrawl (web scraping & search)

Firecrawl gives Hermes the ability to scrape, crawl, and extract content from websites. Running it locally keeps all data on your machine and avoids API rate limits.

```bash
bash install_firecrawl_docker.sh
```

Then tell Hermes where to find it by adding this line to `~/.hermes/.env` and restarting the gateway:

```bash
FIRECRAWL_API_URL=http://localhost:3002
```

> Full guide: [Fix Firecrawl & Browser on Headless Linux](Doc/fix-firecrawl-and-browser.md)

---

#### Step B — Autostart Services at Boot (no login required)

Makes Firecrawl and Chrome CDP start automatically when the machine boots — even before any user logs in.

```bash
sudo bash install_autostart_services.sh
```

This creates and enables two systemd services:

| Service | What it starts | Port |
|---|---|---|
| `firecrawl.service` | Firecrawl Docker stack | 3002 |
| `chrome-cdp.service` | Chrome headless + CDP remote debugging | 9222 |

> **Note:** The native Hermes gateway is already managed by its own user service, installed automatically by `hermes gateway install` during setup. Run `hermes gateway status` to check it.

Post-install management:

```bash
# System services installed by this script
sudo systemctl status  firecrawl chrome-cdp
sudo systemctl restart firecrawl
sudo journalctl -u chrome-cdp -f

# The Hermes gateway is a *user* service — no sudo
systemctl --user status hermes-gateway
journalctl --user -u hermes-gateway -f
```

---

#### Step C — Chrome DevTools MCP Server (authenticated browser sessions)

Connects Hermes to a real Chrome browser via the Chrome DevTools Protocol (CDP). Required for:

- Web pages that need a logged-in user (Gmail, Twitter/X, LinkedIn, etc.)
- Sites behind a firewall or paywall with no public API
- Sites whose API is paid or unavailable

If you ran Step B, Chrome is already running headlessly on port 9222 at boot. To take over with a visible Chrome window after login, use the included helper script:

```bash
bash chrome_remote_debug.sh
```

This stops the headless `chrome-cdp` service, opens a visible Chrome window on the same port and profile, then **automatically restarts the headless service** when you close Chrome or the terminal.

To launch Chrome manually without the script (if autostart is not installed):

```bash
google-chrome \
  --remote-debugging-port=9222 \
  --user-data-dir=$HOME/.config/google-chrome-ai-agent
```

Then add to `~/.hermes/config.yaml`:

```yaml
mcp_servers:
  chrome-devtools:
    command: "npx"
    args: ["-y", "chrome-devtools-mcp@latest", "--browser-url=http://127.0.0.1:9222"]
    timeout: 60
    connect_timeout: 30
```

> Full guide: [Install Chrome DevTools MCP Server](Doc/install-mcp-chrome-dev-tools.md)

> ⚠️ **Security warning:** Chrome DevTools MCP gives Hermes full control over a real browser window, including access to all cookies, saved passwords, and active sessions in that profile. Use a **dedicated Chrome profile** (the `--user-data-dir` flag above) — never point it at your personal profile. Only enable this when you need it for sites with no API alternative. The risk is real but manageable with a separate profile.

---

#### Step D — Obsidian Knowledge Base (with plugins)

Installs [Obsidian](https://obsidian.md) and pre-downloads 11 community plugins into a ready-to-use vault at `~/Obsidian`.

```bash
bash extras/install_obsidian.sh              # vault at ~/Obsidian (default)
bash extras/install_obsidian.sh ~/my/vault   # or a custom path
```

Plugins included: **Kanban, Dataview, Templater, Git, Tasks, Excalidraw, Calendar, QuickAdd, Advanced Tables, Smart Connections, Copilot**

After running, open Obsidian, open `~/Obsidian` as your vault, then go to **Settings → Community plugins** to enable each plugin.

> See [Nice-to-Have Tools & Skills](Doc/nice_to_have_tools_and_skills.md) for descriptions of all recommended extras.

---

## 📂 Documentation

| Guide | Description |
|---|---|
| [Fix Firecrawl & Browser on Headless Linux](Doc/fix-firecrawl-and-browser.md) | Resolving missing system libraries, sandbox issues, and `--no-sandbox` configuration |
| [Autostart Services at Boot](install_autostart_services.sh) | Systemd services for Firecrawl and Chrome CDP — start at boot without login |
| [Chrome Remote Debug Helper](chrome_remote_debug.sh) | Switch from headless CDP service to a visible Chrome window and back |
| [Nice-to-Have Tools & Skills](Doc/nice_to_have_tools_and_skills.md) | Recommended extras: Firecrawl, Chrome DevTools MCP, Context7 |
| [Obsidian + Plugins Installer](extras/install_obsidian.sh) | Installs Obsidian and 11 community plugins into a pre-configured vault |
| [Install a Secondary Hermes Agent in Docker](Doc/install-secondary-hermes-docker.md) | Run a second, isolated Hermes gateway in Docker alongside a bare-metal install |
| [Install Chrome DevTools MCP Server](Doc/install-mcp-chrome-dev-tools.md) | Setting up browser automation with persistent sessions via CDP |
| [Migrate from OpenClaw](Doc/openclaw_migration.md) | Archiving your OpenClaw workspace and importing data into Hermes |

---

## 🛠️ What's Included

```
hermes-installation-toolkit/
├── README.md                          # You are here
├── Doc/
│   ├── fix-firecrawl-and-browser.md   # Firecrawl deps + browser sandbox fix
│   ├── install-secondary-hermes-docker.md # Second isolated Hermes in Docker
│   ├── install-mcp-chrome-dev-tools.md # Chrome DevTools MCP setup guide
│   ├── nice_to_have_tools_and_skills.md # Recommended extras: Firecrawl, CDP, Context7
│   └── openclaw_migration.md          # OpenClaw → Hermes migration steps
├── install_hermes.sh                  # One-liner: curl installer wrapper
├── install_firecrawl_docker.sh        # Self-hosted Firecrawl via Docker Compose
├── install_autostart_services.sh      # Systemd autostart: Firecrawl + Chrome CDP
├── chrome_remote_debug.sh             # Switch headless CDP → visible Chrome window
├── docker/
│   ├── hermes_docker_secondary.sh             # Secondary Docker Hermes helper
│   └── docker-compose.hermes-secondary.yml  # Secondary Docker Hermes Compose service
└── extras/
    └── install_obsidian.sh                  # Obsidian + 11 community plugins installer
```

---

## 🐳 Secondary Hermes in Docker (Alongside Bare-Metal)

If you already run Hermes on bare-metal and want a second isolated instance in Docker:

```bash
# 1) One-time setup wizard for the Docker instance
bash docker/hermes_docker_secondary.sh setup

# 2) Start the Docker gateway
bash docker/hermes_docker_secondary.sh start

# 3) Follow logs
bash docker/hermes_docker_secondary.sh logs
```

Defaults used by this toolkit:

- Bare-metal data: `~/.hermes`
- Docker data: `~/.hermes-secondary`
- Docker API host port: `8643` (mapped to container `8642`)

Quick interactive chat from the container:

```bash
bash docker/hermes_docker_secondary.sh shell
hermes
```

Full guide: [Install a Secondary Hermes Agent in Docker](Doc/install-secondary-hermes-docker.md)

---

## ⚙️ Post-Installation Commands

```bash
hermes setup              # Re-run the full configuration wizard
hermes setup model        # Change model / provider
hermes config             # View current settings
hermes config edit        # Open config.yaml in your editor
hermes gateway start      # Launch messaging + cron gateway
hermes doctor             # Diagnose common issues
hermes update             # Pull latest version & bundled skills
```

---

## 📁 Where Files Live

After installation, everything is under `~/.hermes/`:

- **Config:** `~/.hermes/config.yaml`
- **API Keys:** `~/.hermes/.env`
- **Data:** `~/.hermes/cron/`, `~/.hermes/sessions/`, `~/.hermes/logs/`
- **Agent Code:** `~/.hermes/hermes-agent/`

---

## 📌 Notes

- This toolkit was built from a real-world installation on Ubuntu with a fully local LLM (no cloud API keys required for inference).
- All scripts and guides are tested but may need minor adjustments depending on your distro or hardware.
- Feel free to open an issue or submit a PR if you spot something outdated!
