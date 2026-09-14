# Installing Chrome DevTools MCP Server on Hermes Agent

This guide documents how to set up the [Chrome DevTools MCP](https://github.com/ChromeDevTools/chrome-devtools-mcp) server with Hermes Agent for browser automation, web scraping, authenticated sessions, and DOM inspection.

---

## Table of Contents

- [What Is Chrome DevTools MCP?](#what-is-chrome-devtools-mcp)
- [Prerequisites](#prerequisites)
- [Step 1: Install Google Chrome (Non-Sandboxed)](#step-1-install-google-chrome-non-sandboxed)
- [Step 2: Start Chrome with Remote Debugging](#step-2-start-chrome-with-remote-debugging)
- [Step 3: Configure Hermes Agent](#step-3-configure-hermes-agent)
- [Step 4: Verify the Setup](#step-4-verify-the-setup)
- [Available Tools](#available-tools)
- [Authentication Workflows](#authentication-workflows)
- [Known Issues & Troubleshooting](#known-issues--troubleshooting)
- [Important Notes](#important-notes)
- [Related Guide](#related-guide)

---

## Related Guide

If you want to run Hermes on bare-metal and also keep a second isolated Hermes instance in Docker, follow:

- [Install a Secondary Hermes Agent in Docker](install-secondary-hermes-docker.md)

---

## What Is Chrome DevTools MCP?

Chrome DevTools MCP is a **Model Context Protocol (MCP)** server that exposes browser capabilities through the [Chrome DevTools Protocol (CDP)](https://chromedevtools.github.io/devtools-protocol/). It enables:

- **Browser automation** — navigate pages, click elements, fill forms
- **DOM inspection** — accessibility tree snapshots with element UIDs
- **Screenshots** — visual capture of full pages and individual elements
- **Network monitoring** — inspect HTTP requests and responses in real time
- **JavaScript execution** — evaluate arbitrary scripts in the page context
- **Persistent sessions** — authentication state survives across tool calls

This is especially useful for web scraping behind paywalls, logging into websites programmatically, and automating browser workflows without headless Selenium/Puppeteer overhead.

---

## Prerequisites

- **Node.js & npm** installed (for `npx`)
- **Hermes Agent** configured and running
- **Google Chrome or Chromium** (non-snap) installed on the system
- **Chrome launched manually** with `--remote-debugging-port` and a **dedicated profile directory** (see Step 2)

---

## Step 1: Install Google Chrome (Non-Sandboxed)

### ⚠️ Critical: Do NOT Use Snap Chromium

Snap-installed Chromium runs in a sandbox that blocks Chrome DevTools Protocol (CDP) connections. This is a hard constraint — CDP simply won't work with Snap packages.

```bash
# ❌ DO NOT USE — Snap packages will fail
which chromium  # if this resolves to /usr/bin/snap, it's sandboxed

# ✅ Check for non-sandboxed browser
which google-chrome-stable
# → /usr/bin/google-chrome-stable
```

### Installing Google Chrome on Ubuntu / Debian

```bash
wget -q -O /tmp/google-chrome.deb \
  https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb
sudo dpkg -i /tmp/google-chrome.deb
sudo apt-get install -f -y   # Fix missing dependencies if needed
rm /tmp/google-chrome.deb
```

### Verifying the Installation

```bash
google-chrome-stable --version
# → e.g., "Google Chrome 125.0.xxxx.xx"
```

---

## Step 2: Start Chrome with Remote Debugging (Recommended)

**Before configuring Hermes Agent, you must start Chrome manually** with remote debugging enabled and a **dedicated profile directory**. This is the recommended approach because:

- ✅ Authentication state (cookies, logins) **persists across Hermes Agent restarts**
- ✅ Your AI agent browser session is **isolated** from your personal Chrome profile
- ✅ You maintain full control over the browser lifecycle
- ✅ Works reliably with cron jobs and long-running sessions

### Launching Chrome

```bash
# Recommended: Start Chrome with a dedicated AI-agent profile
google-chrome-stable \
  --remote-debugging-port=9222 \
  --user-data-dir=/home/$USER/.config/google-chrome-ai-agent
```

> **⚠️ Why a separate `--user-data-dir`?**
>
> Using a dedicated profile directory keeps your AI agent's browser data (cookies, history, cache) completely separate from your personal Chrome profile. This means:
> - Your personal bookmarks, passwords, and extensions stay untouched
> - The AI agent can log into services without polluting your main profile
> - You can safely clear the AI agent profile without affecting daily browsing
> - You can run both profiles simultaneously

### Verifying Chrome is Ready

After launching, check that the debugging port is active:

```bash
curl -s http://127.0.0.1:9222/json/version
```

You should see JSON output with your Chrome version and webSocket URL:

```json
{
  "Browser": "Chrome/125.0.xxxx.xx",
  "Protocol-Version": "1.3",
  "webSocketURL": "ws://127.0.0.1:9222/devtools/browser/..."
}
```

### Auto-Start on Login (Optional)

To have Chrome with remote debugging start automatically, add a desktop entry:

```bash
mkdir -p ~/.config/autostart

# Unquoted EOF on purpose: $HOME must expand now, because .desktop files
# do not expand shell variables in Exec=.
cat > ~/.config/autostart/chrome-ai-agent.desktop << EOF
[Desktop Entry]
Type=Application
Name=Chrome AI Agent
Exec=google-chrome-stable --remote-debugging-port=9222 --user-data-dir=$HOME/.config/google-chrome-ai-agent
Hidden=false
NoDisplay=false
X-GNOME-Autostart-enabled=true
EOF
```

---

## Step 3: Configure Hermes Agent

Add the MCP server entry to your `~/.hermes/config.yaml`:

```yaml
mcp_servers:
  chrome-devtools:
    command: "npx"
    args: ["-y", "chrome-devtools-mcp@latest", "--browser-url=http://127.0.0.1:9222"]
    timeout: 60
    connect_timeout: 30
```

### Configuration Explained

| Parameter | Value | Description |
|---|---|---|
| `command` | `npx` | Runs the MCP server via npx (auto-installs on first run) |
| `args` | `-y chrome-devtools-mcp@latest` | Pulls latest version without prompts |
| `--browser-url` | `http://127.0.0.1:9222` | **Recommended** — connects to your manually-launched Chrome instance |
| `timeout` | `60` | Request timeout in seconds (increase for slow pages) |
| `connect_timeout` | `30` | Connection timeout for CDP handshake |

### Alternative: Let MCP Manage the Browser (Not Recommended)

If you prefer MCP to launch Chrome automatically, use `--executable-path` instead:

```yaml
mcp_servers:
  chrome-devtools:
    command: "npx"
    args: ["-y", "chrome-devtools-mcp@latest", "--executable-path=/usr/bin/google-chrome-stable"]
    timeout: 60
    connect_timeout: 30
```

> **⚠️ Limitations of MCP-managed browser:**
> - Browser lifecycle is tied to the MCP server process — if MCP restarts, you lose all sessions
> - No persistent profile — every launch starts fresh (no saved logins/cookies)
> - Cron jobs get isolated sessions that don't share cookies with interactive sessions
> - Less control over Chrome flags and profile configuration

---

## Step 4: Verify the Setup

After saving `config.yaml`, restart Hermes Agent. The MCP server auto-starts on next invocation.

### Quick Checklist

1. Chrome is running with `--remote-debugging-port=9222` ✅
2. `curl http://127.0.0.1:9222/json/version` returns JSON ✅
3. Hermes Agent config has `--browser-url=http://127.0.0.1:9222` ✅
4. Hermes Agent restarted ✅

### Test Navigation

```
mcp_chrome_devtools_navigate_page(url="https://example.com", type="url")
```

### Take a Snapshot

```
mcp_chrome_devtools_take_snapshot(verbose=false)
```

### Expected Output

A text-based accessibility tree with element UIDs:

```
- generic
  - banner
    - heading "Example Domain" [level=1]
    - paragraph
      - StaticText "This domain is for use in illustrative examples..."
      - link "More information..." [uid="e5"]
```

---

## Available Tools

All tools are prefixed with `mcp_chrome_devtools_`:

| Tool | Description |
|---|---|
| `navigate_page` | Navigate to URLs, go back/forward, reload |
| `take_snapshot` | Get text-based DOM snapshot with element UIDs |
| `click` | Click elements by UID (single or double click) |
| `fill` | Type text into input fields |
| `fill_form` | Fill multiple form elements at once |
| `take_screenshot` | Capture visual screenshots (PNG / JPEG / WebP) |
| `list_pages` | List all open tabs and pages |
| `evaluate_script` | Run JavaScript in the page context |
| `hover` | Hover over elements |
| `drag` | Drag-and-drop between elements |
| `upload_file` | Upload files through file inputs |
| `press_key` | Press keyboard keys and shortcuts |
| `list_network_requests` | Inspect HTTP requests and responses |
| `get_network_request` | Get details of a specific network request |
| `list_console_messages` | Read browser console output (logs, errors, warnings) |
| `emulate` | Emulate devices, network throttling, geolocation |
| `lighthouse_audit` | Run Lighthouse accessibility / SEO audits |
| `performance_start_trace` | Start performance profiling traces |

> **Naming convention:** `mcp_{server}_{tool}` with hyphens converted to underscores. Server name `chrome-devtools` becomes `mcp_chrome_devtools_*`.

---

## Authentication Workflows

Chrome DevTools MCP maintains full browser session state across all tool calls. Once you log in, authentication persists for the lifetime of the browser process.

### Example: Logging into Gmail

```
# Step 1: Navigate to Gmail
mcp_chrome_devtools_navigate_page(url="https://mail.google.com", type="url")

# Step 2: Take snapshot to inspect the page
mcp_chrome_devtools_take_snapshot(verbose=false)

# Step 3: If not logged in, fill credentials and submit
mcp_chrome_devtools_fill(uid="e123", value="user@gmail.com")
mcp_chrome_devtools_click(uid="e124")  # Next button
mcp_chrome_devtools_fill(uid="e125", value="password")
mcp_chrome_devtools_click(uid="e126")  # Sign in

# ✅ Session is now authenticated — all subsequent navigations stay logged in
```

### Persistence Guarantees

- Authentication state survives across page navigations within the same session
- Cookies and `localStorage` are preserved while the browser process is alive
- **With `--browser-url` + custom `--user-data-dir`:** Authentication persists even if Hermes Agent restarts, as long as Chrome keeps running
- The browser process stays running as long as you keep it running (or until you close it)

---

## Known Issues & Troubleshooting

### ❌ "Could not connect to Chrome" / "Failed to fetch browser webSocket URL"

**Root cause:** Chrome is not running, or the debugging port is not accessible.
**Fix:**
1. Make sure Chrome was started with `--remote-debugging-port=9222`
2. Verify with: `curl -s http://127.0.0.1:9222/json/version`
3. If Chrome was closed, restart it with the same `--user-data-dir` flag

### ❌ "Protocol error (Target.setDiscoverTargets): Target closed"

**Root cause:** Snap Chromium sandbox blocks CDP connections.
**Fix:** Install Google Chrome via `.deb` package — see [Step 1](#step-1-install-google-chrome-non-sandboxed).

### ❌ Logins Don't Persist / MCP Opens a Fresh Browser

**Root cause:** chrome-devtools-mcp only *warns* about flags it doesn't recognise (`Unknown arguments: ...`) and then keeps running without them. A misspelled connection flag means it never attaches to your Chrome on port 9222 and silently launches its own clean browser instead. Older guides used `--cdp-endpoint` and `--browser-path`, which are not valid flags.
**Fix:** Use `--browser-url=http://127.0.0.1:9222` (connect to running Chrome) or `--executable-path=...` (let MCP launch Chrome), then check the log for warnings:

```bash
grep -a "Unknown arguments" ~/.hermes/logs/mcp-stderr.log | tail
```

### ❌ MCP Server Fails to Start

Check the logs:

```bash
cat ~/.hermes/logs/mcp-stderr.log | grep chrome-devtools
```

Common fixes:
- Verify `--browser-url` points to an accessible Chrome instance
- Ensure Node.js is installed and `npx` works from your shell
- Increase `timeout` if Chrome takes a long time to respond on slow hardware

### ❌ Tools Return "Server Not Available"

The MCP server process may have crashed. Restart Hermes Agent or check whether the Chrome process is still running:

```bash
ps aux | grep chrome-devtools-mcp
ps aux | grep "remote-debugging-port=9222"
```

---

## Important Notes

1. **Always use `--browser-url` with manually-launched Chrome** — This gives you persistent sessions, control over the browser lifecycle, and proper isolation via `--user-data-dir`. The MCP-managed mode (`--executable-path`) is only suitable for quick one-off tasks.

2. **Session persistence across Hermes Agent restarts** — When using `--browser-url`, your Chrome instance keeps running independently. If Hermes Agent restarts (or crashes), the MCP server simply reconnects to the same Chrome instance — all logins and cookies survive.

3. **Cron jobs share the same Chrome session** — Because Chrome runs independently with `--browser-url`, cron jobs connect to the same browser instance and inherit all authentication state. This is perfect for monitoring tasks that need logged-in access.

4. **Snap = No CDP** — This is a hard constraint. If Ubuntu auto-installed Chromium via snap, switch to Google Chrome or install from the official PPA.

5. **Timeout tuning** — For pages with heavy JavaScript (SPAs, paywalled content), increase `timeout: 60` to `120` or higher.

6. **Element UIDs are dynamic** — The `uid` values in snapshots change between page loads. Always take a fresh snapshot before clicking or filling elements.

7. **Chrome process resilience** — If Chrome crashes or gets closed, you need to restart it manually with the same `--user-data-dir` flag. All saved sessions (cookies, logins) are restored from the profile directory.

---

## References

- [Chrome DevTools MCP on GitHub](https://github.com/ChromeDevTools/chrome-devtools-mcp)
- [Hermes Agent Documentation](https://hermes-agent.nousresearch.com/docs)
- [Chrome DevTools Protocol (CDP)](https://chromedevtools.github.io/devtools-protocol/)
