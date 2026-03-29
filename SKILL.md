---
name: chrome-cdp-setup
description: "Set up Chrome DevTools Protocol (CDP) for OpenClaw browser automation. One-click setup to let OpenClaw agents control the user's main Chrome browser (with login state, cookies, extensions) via CDP remote debugging. Use when: (1) user wants agent to control their real browser, (2) browser automation fails with 'DevToolsActivePort not found', (3) CDP connection refused on port 9222, (4) proxy software (Surge/Clash) causes SSRF blocks on web_fetch or media download. Covers macOS (LaunchAgent) and Linux (systemd)."
---

# Chrome CDP Setup

One-click Chrome DevTools Protocol configuration for OpenClaw browser automation.

## Quick Start

### First-time setup

```bash
bash scripts/setup.sh
```

Handles everything: Chrome detection, CDP data directory creation, profile symlinking, auto-start service, OpenClaw config update, and proxy SSRF detection.

### Verify connectivity

```bash
bash scripts/verify.sh
```

Full diagnostic: Chrome process, port 9222, CDP endpoint, DevToolsActivePort, OpenClaw config.

### Fix proxy SSRF (Surge/Clash)

```bash
bash scripts/patch-ssrf.sh
```

Patches OpenClaw's SSRF filter to allow RFC 2544 range (198.18.x.x) used by proxy DNS. Must re-run after OpenClaw updates.

## How It Works

Chrome refuses `--remote-debugging-port` on its default user-data-dir. The setup script creates `~/.chrome-cdp-data/` with:
- Copies of `Local State` and `First Run` from the real Chrome profile
- A symlink `Default` → original Chrome profile's `Default` directory

This preserves all login state, cookies, and extensions while satisfying Chrome's requirement.

## Auto-start

- **macOS**: LaunchAgent at `~/Library/LaunchAgents/com.openclaw.chrome-cdp.plist`
- **Linux**: systemd user service at `~/.config/systemd/user/chrome-cdp.service`

## Troubleshooting

See `references/troubleshooting.md` for common issues: port conflicts, profile locks, proxy DNS, LaunchAgent debugging.
