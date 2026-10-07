# Nice-to-Have Tools & Skills for Hermes Agent

Recommended extras that significantly extend what Hermes can do. All of these are installed and working on this system.

---

## 1. Firecrawl — Web Scraping & Crawling

**What it does:** Gives Hermes the ability to scrape, crawl, and extract structured content from any website. Powers the `web_search` and `web_extract` tools. Running it locally means no API rate limits, no data leaving the machine, and no cost per request.

**Why it's worth it:** Without Firecrawl, Hermes can only read pages via basic HTTP. With it, the agent can crawl entire sites, handle JavaScript-rendered content, extract clean Markdown from any URL, and run deep research tasks autonomously.

**Install:**
```bash
bash install_firecrawl_docker.sh
```

Firecrawl runs as a Docker stack (API + Playwright browser + Redis + RabbitMQ + Postgres). After install it listens on `http://localhost:3002`. The script works on x86-64 and arm64. On arm64 or low-RAM machines it adds a Compose override and lighter concurrency settings automatically.

To make it start at boot automatically:
```bash
sudo bash install_autostart_services.sh
```

**Config in `~/.hermes/.env`** (Firecrawl is configured by environment variable, not in `config.yaml`):
```bash
FIRECRAWL_API_URL=http://localhost:3002
```

**Docs:** [Fix Firecrawl & Browser on Headless Linux](fix-firecrawl-and-browser.md)

---

## 2. Chrome DevTools MCP — Authenticated Browser Sessions

**What it does:** Connects Hermes to a real Chrome browser via the Chrome DevTools Protocol (CDP). Hermes can navigate pages, click, fill forms, take screenshots, inspect the DOM, run JavaScript, and monitor network traffic — all inside a persistent browser session.

**Why it's worth it:** Firecrawl handles anonymous public content well, but it can't log into sites. Chrome DevTools MCP fills that gap — it lets Hermes operate inside an authenticated Chrome session, so it can access Gmail, LinkedIn, Twitter/X, paywalled sites, internal dashboards, or anything else that requires a real logged-in browser.

**Install Chrome and start it with remote debugging:**
```bash
# One-time: install Chrome (x86-64 only; on arm64 skip this, the scripts
# fall back to the Chromium that Hermes downloads into ~/.hermes/tools)
wget -q -O /tmp/chrome.deb https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb
sudo dpkg -i /tmp/chrome.deb && sudo apt-get install -f -y

# Start Chrome with CDP (or use the helper script below)
bash chrome_remote_debug.sh
```

The `chrome_remote_debug.sh` script handles the case where the headless `chrome-cdp` systemd service is already running — it stops the service, opens a visible Chrome window, then restarts the headless service when you close Chrome.

**Config in `~/.hermes/config.yaml`:**
```yaml
mcp_servers:
  chrome-devtools:
    command: "npx"
    args: ["-y", "chrome-devtools-mcp@latest", "--browser-url=http://127.0.0.1:9222"]
    timeout: 60
    connect_timeout: 30
```

> ⚠️ **Security:** Always use a dedicated Chrome profile (`--user-data-dir`). Never point CDP at your personal browser profile — the agent gets full access to all cookies and saved passwords in that profile.

**Docs:** [Install Chrome DevTools MCP Server](install-mcp-chrome-dev-tools.md)

---

## 3. Context7 — Up-to-Date Library Documentation

**What it does:** An MCP server that fetches current, version-accurate documentation for any programming library or framework directly from the source. When Hermes writes code, it can look up the real API docs instead of relying on training data that may be outdated.

**Why it's worth it:** LLMs (including Hermes) are trained on snapshots of the internet. Library APIs change. Context7 solves the "hallucinated API" problem — Hermes can resolve library docs on demand, so the code it writes uses the actual current API, not a version from a year ago.

**Example:** Ask Hermes to write code using a recent version of LangChain, FastAPI, or any other rapidly evolving library — it will fetch live docs rather than guess.

**Install (add to `~/.hermes/config.yaml`):**
```yaml
mcp_servers:
  context7:
    command: "npx"
    args: ["-y", "@upstash/context7-mcp@latest"]
    timeout: 60
    connect_timeout: 30
```

No other setup required — `npx` downloads and runs it on demand.

**Usage:** Once configured, Hermes automatically uses Context7 when it needs library documentation. You can also ask explicitly: *"Use context7 to look up the FastAPI routing docs."*

**Source:** [github.com/upstash/context7](https://github.com/upstash/context7)
