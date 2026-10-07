# Browser Automation in Hermes: CDP, `browser.cdp_url` and Chrome DevTools MCP

> **Applies to:** Hermes Agent v0.21+ on Linux (x86_64 and arm64, incl. Raspberry Pi 4)
> **TL;DR:** CDP is the protocol, not a product. Hermes already speaks it to its own private Chromium out of the box. `chrome-cdp.service` + `browser.cdp_url` swap that for one always-on shared browser, and Chrome DevTools MCP is an *optional extra client* on top of the same port.

---

## Table of Contents

- [What CDP Is](#what-cdp-is)
- [What Hermes Does by Default](#what-hermes-does-by-default)
- [Persistent Browser: `chrome-cdp.service` + `browser.cdp_url`](#persistent-browser-chrome-cdpservice--browsercdp_url)
- [CDP vs. Chrome DevTools MCP](#cdp-vs-chrome-devtools-mcp)
- [Which Setup Should I Use?](#which-setup-should-i-use)
- [Raspberry Pi / arm64 Notes](#raspberry-pi--arm64-notes)
- [Verify It Works](#verify-it-works)
- [Security](#security)

---

## What CDP Is

**CDP = Chrome DevTools Protocol.** It is the remote-control interface built into Chrome and Chromium.

- Start the browser with `--remote-debugging-port=9222` and it accepts commands on that port.
- A client connects over WebSocket and sends JSON commands: *open this URL*, *click this element*, *take a screenshot*, *run this JavaScript*.
- The browser streams back results and events: page loads, network requests, console errors.

The DevTools panel you open with **F12** is itself just a CDP client. So are Puppeteer, Playwright, `agent-browser` and Hermes' Browser Use backend.

Headless vs. visible window is **unrelated** to CDP: it is only how the browser is launched. CDP works the same in both.

---

## What Hermes Does by Default

With no browser configuration at all, Hermes already uses CDP. You just never see it:

1. On install, Hermes downloads its own Chromium build into `~/.hermes/tools/chromium-<build>/` (plus the `agent-browser` CLI). No Google Chrome, snap or apt package is needed.
2. When the agent needs a browser, Hermes **launches that Chromium on demand**, connects to it over an internal CDP port, and drives it.
3. The browser is **private to the session** and is closed after inactivity (`browser.inactivity_timeout`, default 120 s).

Resolution order Hermes uses to pick a browser (from `tools/browser_use_cli.py`):

1. `BU_CDP_URL` / `BU_CDP_WS` env (operator override)
2. `BROWSER_CDP_URL` env or **`browser.cdp_url`** in `config.yaml`
3. A cloud provider (Browserbase, Browser Use cloud, …) if configured
4. The local packaged Chromium (the default described above)

So you do **not** need to install Chrome or run a CDP service for Hermes' browser tools to work.

---

## Persistent Browser: `chrome-cdp.service` + `browser.cdp_url`

[`install_autostart_services.sh`](../install_autostart_services.sh) creates `chrome-cdp.service`, which keeps one headless browser running from boot on a **fixed port 9222** with a dedicated profile (`~/.config/google-chrome-ai-agent`). It uses Google Chrome if installed, otherwise the Chromium bundled with Hermes.

Point Hermes at it in `~/.hermes/config.yaml`:

```yaml
browser:
  cdp_url: "http://localhost:9222"
```

Then restart the gateway:

```bash
hermes gateway restart
```

Hermes now attaches to that browser instead of launching its own.

| | Default (managed Chromium) | `chrome-cdp.service` + `cdp_url` |
|---|---|---|
| Who starts the browser | Hermes, on demand | systemd, at boot |
| CDP port | internal, random, hidden | fixed `9222` |
| Lifetime | per session, closed when idle | always running |
| Cookies / logins / open tabs | discarded with the session | kept across sessions and reboots (profile on disk) |
| Other clients (DevTools MCP, your own scripts) | cannot attach | can attach to the same browser |
| RAM | only while browsing | always (~300–500 MB) |

> **`hermes doctor` shows `⚠ browser-cdp (system dependency not met)`?** That is expected in the default Browser Use mode. The standalone `browser_cdp` tool is replaced there by `browser_exec`, which still honours `browser.cdp_url`.

---

## CDP vs. Chrome DevTools MCP

They are different layers, not two names for the same thing:

| | Chrome DevTools Protocol (CDP) | Chrome DevTools MCP |
|---|---|---|
| What it is | a **protocol** the browser speaks | a **program**: an MCP server by Google |
| Role | the browser receives commands through it | translates AI-agent tool calls into CDP commands |
| Used by | DevTools (F12), Puppeteer, Playwright, Hermes, … | AI agents via MCP |

```
Hermes built-in browser tools:
  Hermes (Browser Use) ──CDP──────────────────────────► Chromium :9222

With Chrome DevTools MCP added:
  Hermes ──MCP──► chrome-devtools-mcp ──CDP──────────► Chromium :9222
```

Chrome DevTools MCP adds debugging-oriented tools on top: network traffic analysis, performance traces, deep DOM and console inspection. For ordinary browsing (open, click, fill forms, read pages) Hermes' built-in tools are enough. If you do add the MCP server, point it at the same port so no second browser is started. See [Install Chrome DevTools MCP Server](install-mcp-chrome-dev-tools.md).

---

## Which Setup Should I Use?

- **Just want web browsing to work** → do nothing; the default managed Chromium is fine.
- **Want the agent to stay logged into sites, or keep tabs between tasks** → `chrome-cdp.service` + `browser.cdp_url`.
- **Want web debugging / performance tooling for the agent** → additionally add Chrome DevTools MCP on port 9222.
- **Low-RAM machine** (e.g. Raspberry Pi with 8 GB shared with Firecrawl) → prefer the default; an always-on browser costs memory even when idle.

---

## Raspberry Pi / arm64 Notes

- **Google Chrome has no Linux arm64 build.** `install_autostart_services.sh` falls back to the Chromium Hermes downloaded (`~/.hermes/tools/chromium-*/chrome-linux/chrome`), which is a native arm64 build. Override with `sudo CHROME_BIN=/path/to/chrome ./install_autostart_services.sh`.
- **Avoid snap Chromium** for CDP. Its sandbox restricts the profile location and blocks CDP connections.
- The bundled Chromium path contains a build number. If a `hermes update` replaces it and `chrome-cdp.service` stops starting, re-run `sudo ./install_autostart_services.sh`.
- Give the Pi enough swap (4 GB worked well) before running an always-on browser next to Firecrawl.

---

## Verify It Works

```bash
# Service is running and enabled at boot
systemctl is-enabled chrome-cdp && systemctl is-active chrome-cdp

# CDP endpoint answers
curl -s http://localhost:9222/json/version

# Ask Hermes to browse, then check that the page appeared as a tab in that browser
hermes chat -Q -q "Open https://example.com in the browser and tell me the page title."
curl -s http://localhost:9222/json/list | grep '"url"'
```

Headless Chromium logs errors such as `Failed to connect to the bus`, `PHONE_REGISTRATION_ERROR` or `QUOTA_EXCEEDED` in `journalctl -u chrome-cdp`. They are harmless on a machine without a desktop session.

---

## Security

Anyone who can reach port 9222 has **full control** of that browser, including every cookie and logged-in session in its profile.

- Always use a **dedicated profile** (`--user-data-dir`), never your personal one.
- Keep the port local. Chrome binds it to `127.0.0.1` by default; don't expose it or forward it to an untrusted network.
- Only log the agent's browser into accounts you are comfortable letting the agent use.
