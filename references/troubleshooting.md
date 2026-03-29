# Chrome CDP Troubleshooting

## Table of Contents

- [Port 9222 Already in Use](#port-9222-already-in-use)
- [Profile Lock Conflict](#profile-lock-conflict)
- [DevTools Remote Debugging Requires Non-Default Data Directory](#devtools-remote-debugging-requires-non-default-data-directory)
- [Chrome Update Breaks CDP](#chrome-update-breaks-cdp)
- [Proxy DNS / SSRF Blocks](#proxy-dns--ssrf-blocks)
- [LaunchAgent Not Working (macOS)](#launchagent-not-working-macos)
- [systemd Service Not Working (Linux)](#systemd-service-not-working-linux)
- [Symlink vs Hard Copy Profile](#symlink-vs-hard-copy-profile)

---

## Port 9222 Already in Use

**Symptom**: `setup.sh` fails waiting for CDP, or `verify.sh` shows port occupied by non-Chrome process.

**Diagnose**:
```bash
# macOS
lsof -iTCP:9222 -sTCP:LISTEN
# Linux
ss -tlnp | grep 9222
```

**Fix**:
```bash
# Kill the process using port 9222
kill $(lsof -t -iTCP:9222 -sTCP:LISTEN)
# Or use a different port
CDP_PORT=9223 bash scripts/setup.sh
```

---

## Profile Lock Conflict

**Symptom**: Chrome shows "Your profile could not be opened correctly" or fails to start with lock file errors.

**Cause**: Two Chrome instances trying to access the same profile simultaneously. The symlinked `Default` directory means the CDP Chrome and a manually-started Chrome would conflict.

**Fix**:
1. Close all Chrome instances
2. Remove stale lock files:
   ```bash
   rm -f ~/.chrome-cdp-data/Default/lockfile
   rm -f ~/.chrome-cdp-data/Default/SingletonLock
   rm -f ~/.chrome-cdp-data/Default/SingletonSocket
   rm -f ~/.chrome-cdp-data/Default/SingletonCookie
   ```
3. Restart via LaunchAgent or setup script

**Prevention**: Only run Chrome through the CDP setup (LaunchAgent/systemd). Don't start Chrome separately — the symlinked profile means they share the same data.

---

## DevTools Remote Debugging Requires Non-Default Data Directory

**Symptom**: Chrome exits immediately with error: "DevTools remote debugging requires a non-default data directory."

**Cause**: Passing `--remote-debugging-port` while `--user-data-dir` points to Chrome's default profile location.

**Fix**: This is exactly what `setup.sh` solves. It creates `~/.chrome-cdp-data/` as a separate user-data-dir with the Default profile symlinked from the original location.

If the error persists after setup:
```bash
# Verify the CDP data dir is NOT the same as Chrome's default
echo "CDP dir: ~/.chrome-cdp-data"
echo "Chrome default: ~/Library/Application Support/Google/Chrome"  # macOS
# These must be different paths
```

---

## Chrome Update Breaks CDP

**Symptom**: CDP stops working after a Chrome auto-update.

**Common causes**:
- Chrome binary path changed (rare)
- New Chrome version changes CDP behavior
- LaunchAgent references stale binary path

**Fix**:
```bash
# Re-run setup to detect new Chrome path and refresh service
bash scripts/setup.sh
```

---

## Proxy DNS / SSRF Blocks

**Symptom**: OpenClaw's `web_fetch` or media downloads fail with SSRF errors. URLs resolve to `198.18.x.x` range.

**Cause**: Proxy software (Surge, Clash, Quantumult X) uses RFC 2544 benchmarking IPs (198.18.0.0/15) as virtual IPs for DNS-based routing. OpenClaw's SSRF protection blocks this range.

**Diagnose**:
```bash
dig +short google.com
# If result is 198.18.x.x → proxy DNS active
```

**Fix**:
```bash
bash scripts/patch-ssrf.sh
# Then restart gateway
openclaw gateway restart
```

**Note**: The patch modifies `ssrf-*.js` in the OpenClaw installation. After `npm update -g openclaw`, the file is replaced — re-run `patch-ssrf.sh`.

---

## LaunchAgent Not Working (macOS)

**Symptom**: Chrome doesn't start on login, or `launchctl` shows errors.

**Diagnose**:
```bash
# Check if loaded
launchctl list | grep chrome-cdp

# Check for errors
launchctl print gui/$(id -u)/com.openclaw.chrome-cdp

# Check logs
cat ~/Library/Logs/chrome-cdp.log
cat ~/Library/Logs/chrome-cdp.err
```

**Common fixes**:
```bash
# Reload the agent
launchctl unload ~/Library/LaunchAgents/com.openclaw.chrome-cdp.plist
launchctl load ~/Library/LaunchAgents/com.openclaw.chrome-cdp.plist

# If permission denied (SIP/TCC)
# Check System Settings > General > Login Items > Allow in the Background

# Verify plist syntax
plutil ~/Library/LaunchAgents/com.openclaw.chrome-cdp.plist
```

**macOS Sequoia+ note**: Apple tightened background item controls. You may need to explicitly allow the LaunchAgent in System Settings > General > Login Items.

---

## systemd Service Not Working (Linux)

**Diagnose**:
```bash
systemctl --user status chrome-cdp.service
journalctl --user -u chrome-cdp.service -n 50
```

**Common fixes**:
```bash
# Reload and restart
systemctl --user daemon-reload
systemctl --user restart chrome-cdp.service

# If DISPLAY not set (headless/SSH)
export DISPLAY=:0
systemctl --user restart chrome-cdp.service
```

---

## Symlink vs Hard Copy Profile

The setup uses a **symlink** for the Default profile. Here's the tradeoff:

| Aspect | Symlink (default) | Hard Copy |
|--------|-------------------|-----------|
| Login state | ✓ Shared with main Chrome | ✗ Separate (need to re-login) |
| Cookies | ✓ Shared | ✗ Separate |
| Extensions | ✓ Shared | ✗ Must reinstall |
| Storage | ✓ Minimal (~KB) | ✗ Can be GBs |
| Concurrent use | ✗ Can't run both | ✓ Independent |
| Data safety | ✗ CDP Chrome modifies real profile | ✓ Isolated |

**When to hard copy instead**:
- Need to run normal Chrome AND CDP Chrome simultaneously
- Want to isolate CDP browsing from personal browsing
- Automation might modify browser state you want to protect

**To switch to hard copy**:
```bash
rm ~/.chrome-cdp-data/Default
cp -r "$(readlink ~/.chrome-cdp-data/Default)" ~/.chrome-cdp-data/Default
```
Note: This breaks login state sync — changes in one Chrome won't appear in the other.
