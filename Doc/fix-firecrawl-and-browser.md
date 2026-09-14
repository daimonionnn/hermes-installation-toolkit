# Fixing Firecrawl & Browser on Headless Linux

> **Date:** April 28, 2026  
> **System:** Ubuntu 24.04 LTS (headless VM)  
> **Problem:** Firecrawl and `agent-browser` failed due to missing system libraries and Chrome sandbox restrictions

---

## Table of Contents

- [Firecrawl Fix](#firecrawl-fix)
- [Browser (agent-browser) Fix](#browser-agent-browser-fix)
- [File Structure](#file-structure)
- [Verification](#verification)
- [Quick Copy-Paste Summary](#quick-copy-paste-summary)

---

## Firecrawl Fix

### Symptoms

```
Error: Could not find Chrome (ver. 131.0.6778.204).
```

Hermes' browser tooling needs a Chromium runtime plus several system libraries that are absent on minimal Ubuntu server installs.

> **Self-hosted Firecrawl does not need a host browser.** The Docker stack installed by [`install_firecrawl_docker.sh`](../install_firecrawl_docker.sh) ships its own Playwright browser in the `playwright-service` container. If Firecrawl itself misbehaves, check `cd ~/firecrawl && docker compose logs playwright-service api` rather than installing libraries on the host.

### Step 1: Install System Dependencies

```bash
sudo apt-get update && sudo apt-get install -y \
  libatk1.0-0 \
  libatk-bridge2.0-0 \
  libcups2 \
  libxcomposite1 \
  libxss1 \
  libxdamage1 \
  libgbm1 \
  libnss3 \
  fonts-liberation \
  libx11-xcb1 \
  libxkbcommon-x11-0 \
  xdg-utils \
  fonts-noto-color-emoji
```

**What each package does:**

| Package | Purpose |
|---|---|
| `libatk1.0-0`, `libatk-bridge2.0-0` | Accessibility toolkit — required for Chrome UI rendering |
| `libcups2` | CUPS printing library — loaded by Chrome at startup |
| `libxcomposite1` | X11 composite extension for window compositing |
| `libxss1` | X11 Screen Saver extension |
| `libxdamage1` | X11 damage extension for incremental rendering |
| `libgbm1` | Generic Buffer Management — GPU acceleration |
| `libnss3` | Network Security Services — SSL/TLS certificate handling |
| `fonts-liberation` | Liberation fonts — baseline text rendering |
| `libx11-xcb1` | X11 → XCB bridge |
| `libxkbcommon-x11-0` | Keyboard input handling |
| `xdg-utils` | Desktop integration utilities |
| `fonts-noto-color-emoji` | Emoji font support |

### Step 2: Install the Browser and Its Dependencies

```bash
npx agent-browser install --with-deps
```

This downloads Chrome for Testing for [`agent-browser`](https://www.npmjs.com/package/agent-browser) (the browser backend Hermes uses) and, with `--with-deps`, installs the Linux system libraries it needs. It is the same command Hermes suggests in its own error messages.

Alternative, if you prefer Playwright's bundle:

```bash
npx playwright install --with-deps chromium
```

### Step 3: Point Hermes at Self-Hosted Firecrawl

Firecrawl is configured through an environment variable, not `config.yaml`. Add this to `~/.hermes/.env`:

```bash
FIRECRAWL_API_URL=http://localhost:3002
```

Then restart the gateway (`hermes gateway restart`, or `systemctl --user restart hermes-gateway`). Firecrawl should now work as the backend for the `web_search` and `web_extract` tools.

---

## Browser (agent-browser) Fix

### Symptoms

```
[error] [browser] Browser crashed with exit code 1:
[0428/214921.989920:ERROR:zygote_host_impl_linux.cc(97)] No usable sandbox!
```

Chrome/Chromium in headless mode on Linux requires a working sandbox. On systems without nested virtualization (most VPS and cloud servers), the sandbox cannot initialize and Chrome crashes at startup.

### Solution: Disable the Sandbox

#### Method 1: Config File (Recommended ✅)

**File:** `~/.agent-browser/config.json`

```json
{
  "args": "--no-sandbox"
}
```

This config is read on every agent-browser launch and appends `--no-sandbox` to the Chrome command line.

#### Method 2: Environment Variable (Alternative)

**File:** `~/.hermes/.env`

```bash
AGENT_BROWSER_ARGS="--no-sandbox,--disable-dev-shm-usage"
```

Multiple arguments are comma-separated. Recent Hermes versions inject this value automatically when they detect an environment that needs it (running as root, in Docker, or under an AppArmor user-namespace restriction), so you only need to set it by hand if that detection misses your setup.

> **Warning:** After editing `.env`, restart the Hermes gateway so new variables take effect.

### What Does `--no-sandbox` Do?

Normally, Chrome runs child processes inside a Linux sandbox (namespace isolation, seccomp-bpf filters). On headless servers and VPS environments:

- Nested namespaces are often disabled by the host
- Seccomp profiles may conflict with containerization layers
- Sandbox fails to initialize → Chrome crashes on launch

The `--no-sandbox` flag turns this protection off, so a compromised renderer process runs with the full privileges of the user running Hermes. That is an acceptable trade-off on a dedicated agent machine or VM, but keep it in mind:

- Run Hermes as an unprivileged user, never as root
- Prefer a VM or container over your daily desktop account
- On a desktop with a working sandbox, don't set the flag at all

---

## File Structure

```
~/.hermes/
├── .env                          # FIRECRAWL_API_URL, AGENT_BROWSER_ARGS
├── config.yaml                   # Main Hermes Agent configuration
└── ...

~/.agent-browser/
└── config.json                   # { "args": "--no-sandbox" }
```

---

## Verification

### Browser Test

Ask your Hermes agent to run:

```
browser_navigate(url="https://example.com")
```

✅ Should return a page snapshot.

### Firecrawl Test

Ask your Hermes agent to run:

```
web_search(query="test query")
```

✅ Should return search results.

---

## Quick Copy-Paste Summary

```bash
# 1. Install system libraries (for the browser)
sudo apt-get update && sudo apt-get install -y \
  libatk1.0-0 libatk-bridge2.0-0 libcups2 libxcomposite1 \
  libxss1 libxdamage1 libgbm1 libnss3 fonts-liberation \
  libx11-xcb1 libxkbcommon-x11-0 xdg-utils fonts-noto-color-emoji

# 2. Install the browser and its system dependencies
npx agent-browser install --with-deps

# 3. Point Hermes at self-hosted Firecrawl
echo 'FIRECRAWL_API_URL=http://localhost:3002' >> ~/.hermes/.env

# 4. Disable sandbox (only on headless servers / VPS where it crashes)
mkdir -p ~/.agent-browser
echo '{"args": "--no-sandbox"}' > ~/.agent-browser/config.json

# 5. Restart the gateway to pick up .env changes
systemctl --user restart hermes-gateway
```

---

## Notes

- **Firecrawl** is used internally as the backend for `web_search` and `web_extract` — it powers web search and content extraction from URLs.
- **Browser** (`agent-browser`) handles interactive operations: `browser_navigate`, `browser_click`, `browser_type`, `browser_snapshot`.
- On a desktop system with a proper display server, `--no-sandbox` is unnecessary — the sandbox works normally.
- After Hermes Agent updates, verify that `~/.agent-browser/config.json` still exists.
