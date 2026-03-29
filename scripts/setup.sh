#!/usr/bin/env bash
set -euo pipefail

# Chrome CDP Setup - One-click configuration
# Creates a CDP-compatible user-data-dir with symlinked profile

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

CDP_PORT="${CDP_PORT:-9222}"
CDP_DATA_DIR="$HOME/.chrome-cdp-data"

info()    { echo -e "${BLUE}[INFO]${NC} $*"; }
success() { echo -e "${GREEN}[✓]${NC} $*"; }
warn()    { echo -e "${YELLOW}[!]${NC} $*"; }
error()   { echo -e "${RED}[✗]${NC} $*"; exit 1; }

# --- Step 1: Detect OS ---
info "Detecting operating system..."
OS="$(uname -s)"
case "$OS" in
  Darwin) OS_TYPE="macos"; success "macOS detected" ;;
  Linux)  OS_TYPE="linux"; success "Linux detected" ;;
  *)      error "Unsupported OS: $OS" ;;
esac

# --- Step 2: Detect Chrome ---
info "Detecting Chrome installation..."
CHROME_BIN=""
if [[ "$OS_TYPE" == "macos" ]]; then
  for candidate in \
    "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" \
    "$HOME/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"; do
    if [[ -x "$candidate" ]]; then
      CHROME_BIN="$candidate"
      break
    fi
  done
elif [[ "$OS_TYPE" == "linux" ]]; then
  for candidate in google-chrome google-chrome-stable chromium-browser chromium; do
    if command -v "$candidate" &>/dev/null; then
      CHROME_BIN="$(command -v "$candidate")"
      break
    fi
  done
fi
[[ -z "$CHROME_BIN" ]] && error "Chrome not found. Install Google Chrome first."
success "Chrome found: $CHROME_BIN"

# --- Step 3: Detect Chrome default profile directory ---
info "Detecting Chrome default profile directory..."
if [[ "$OS_TYPE" == "macos" ]]; then
  CHROME_DEFAULT_DIR="$HOME/Library/Application Support/Google/Chrome"
elif [[ "$OS_TYPE" == "linux" ]]; then
  CHROME_DEFAULT_DIR="$HOME/.config/google-chrome"
  # Fallback for Chromium
  if [[ ! -d "$CHROME_DEFAULT_DIR" ]]; then
    CHROME_DEFAULT_DIR="$HOME/.config/chromium"
  fi
fi

if [[ ! -d "$CHROME_DEFAULT_DIR" ]]; then
  error "Chrome profile directory not found at: $CHROME_DEFAULT_DIR"
fi
if [[ ! -d "$CHROME_DEFAULT_DIR/Default" ]]; then
  error "Default profile not found at: $CHROME_DEFAULT_DIR/Default"
fi
success "Chrome profile: $CHROME_DEFAULT_DIR"

# --- Step 4: Check if Chrome is running ---
if pgrep -f "Google Chrome" &>/dev/null || pgrep -f "google-chrome" &>/dev/null || pgrep -f "chromium" &>/dev/null; then
  warn "Chrome is currently running."
  echo -e "${YELLOW}Please quit Chrome before continuing.${NC}"
  echo -e "Press Enter after closing Chrome, or Ctrl+C to abort."
  read -r
  # Re-check
  if pgrep -f "Google Chrome" &>/dev/null || pgrep -f "google-chrome" &>/dev/null || pgrep -f "chromium" &>/dev/null; then
    error "Chrome is still running. Please quit Chrome and try again."
  fi
fi
success "Chrome is not running"

# --- Step 5: Create CDP data directory with symlinked profile ---
info "Setting up CDP data directory: $CDP_DATA_DIR"
mkdir -p "$CDP_DATA_DIR"

# Copy Local State (required by Chrome for multi-profile management)
if [[ -f "$CHROME_DEFAULT_DIR/Local State" ]]; then
  cp -f "$CHROME_DEFAULT_DIR/Local State" "$CDP_DATA_DIR/Local State"
  info "Copied Local State"
fi

# Copy First Run marker (suppresses first-run dialog)
if [[ -f "$CHROME_DEFAULT_DIR/First Run" ]]; then
  cp -f "$CHROME_DEFAULT_DIR/First Run" "$CDP_DATA_DIR/First Run"
  info "Copied First Run"
else
  touch "$CDP_DATA_DIR/First Run"
  info "Created First Run marker"
fi

# Symlink Default profile → original profile (preserves login state, cookies, extensions)
if [[ -L "$CDP_DATA_DIR/Default" ]]; then
  rm -f "$CDP_DATA_DIR/Default"
fi
if [[ -d "$CDP_DATA_DIR/Default" ]]; then
  warn "A real Default directory exists in CDP data dir. Removing to create symlink."
  rm -rf "$CDP_DATA_DIR/Default"
fi
ln -sf "$CHROME_DEFAULT_DIR/Default" "$CDP_DATA_DIR/Default"
success "Symlinked Default profile → $CHROME_DEFAULT_DIR/Default"

# --- Step 6: Create auto-start service ---
if [[ "$OS_TYPE" == "macos" ]]; then
  info "Creating macOS LaunchAgent..."
  PLIST_PATH="$HOME/Library/LaunchAgents/com.openclaw.chrome-cdp.plist"
  mkdir -p "$HOME/Library/LaunchAgents"

  cat > "$PLIST_PATH" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>com.openclaw.chrome-cdp</string>
  <key>ProgramArguments</key>
  <array>
    <string>${CHROME_BIN}</string>
    <string>--remote-debugging-port=${CDP_PORT}</string>
    <string>--user-data-dir=${CDP_DATA_DIR}</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <false/>
  <key>StandardOutPath</key>
  <string>${HOME}/Library/Logs/chrome-cdp.log</string>
  <key>StandardErrorPath</key>
  <string>${HOME}/Library/Logs/chrome-cdp.err</string>
</dict>
</plist>
PLIST

  success "LaunchAgent created: $PLIST_PATH"

elif [[ "$OS_TYPE" == "linux" ]]; then
  info "Creating systemd user service..."
  SERVICE_DIR="$HOME/.config/systemd/user"
  SERVICE_PATH="$SERVICE_DIR/chrome-cdp.service"
  mkdir -p "$SERVICE_DIR"

  cat > "$SERVICE_PATH" <<SERVICE
[Unit]
Description=Chrome CDP Remote Debugging
After=graphical-session.target

[Service]
Type=simple
ExecStart=${CHROME_BIN} --remote-debugging-port=${CDP_PORT} --user-data-dir=${CDP_DATA_DIR}
Restart=on-failure
RestartSec=5

[Install]
WantedBy=default.target
SERVICE

  systemctl --user daemon-reload
  systemctl --user enable chrome-cdp.service
  success "systemd service created and enabled: $SERVICE_PATH"
fi

# --- Step 7: Start Chrome with CDP ---
info "Starting Chrome with CDP on port $CDP_PORT..."
if [[ "$OS_TYPE" == "macos" ]]; then
  # Unload first in case it's already loaded (ignore errors)
  launchctl unload "$PLIST_PATH" 2>/dev/null || true
  launchctl load "$PLIST_PATH"
elif [[ "$OS_TYPE" == "linux" ]]; then
  systemctl --user start chrome-cdp.service
fi

# --- Step 8: Wait for CDP to become available ---
info "Waiting for CDP to become available on port $CDP_PORT..."
MAX_WAIT=30
WAITED=0
while ! curl -sf "http://127.0.0.1:${CDP_PORT}/json/version" &>/dev/null; do
  sleep 1
  WAITED=$((WAITED + 1))
  if [[ $WAITED -ge $MAX_WAIT ]]; then
    error "Timed out waiting for CDP after ${MAX_WAIT}s. Check Chrome logs."
  fi
done
success "CDP is available on port $CDP_PORT (took ${WAITED}s)"

# Show version info
CDP_VERSION=$(curl -sf "http://127.0.0.1:${CDP_PORT}/json/version" 2>/dev/null || echo "{}")
BROWSER_VER=$(echo "$CDP_VERSION" | grep -o '"Browser":"[^"]*"' | cut -d'"' -f4)
[[ -n "$BROWSER_VER" ]] && info "Browser: $BROWSER_VER"

# --- Step 9: Detect proxy software (SSRF conflict) ---
PROXY_DETECTED=false
info "Checking for proxy software (Surge/Clash)..."
# Test if a known domain resolves to 198.18.x.x range
TEST_IP=""
if command -v dig &>/dev/null; then
  TEST_IP=$(dig +short google.com 2>/dev/null | head -1)
elif command -v nslookup &>/dev/null; then
  TEST_IP=$(nslookup google.com 2>/dev/null | awk '/^Address: / { print $2 }' | tail -1)
fi

if [[ "$TEST_IP" == 198.18.* ]]; then
  PROXY_DETECTED=true
  warn "Proxy software detected (DNS resolves to $TEST_IP)"
  warn "This may cause SSRF blocks in OpenClaw."
  echo -e "${YELLOW}  Run: bash scripts/patch-ssrf.sh${NC}"
else
  success "No proxy SSRF conflict detected"
fi

# --- Step 10: Update OpenClaw configuration ---
info "Updating OpenClaw configuration..."
OPENCLAW_CONFIG="$HOME/.openclaw/openclaw.json"

if [[ -f "$OPENCLAW_CONFIG" ]]; then
  # Check if jq is available for clean JSON editing
  if command -v jq &>/dev/null; then
    TEMP_CONFIG=$(mktemp)
    jq --arg port "$CDP_PORT" --arg dir "$CDP_DATA_DIR" '
      .browser = (.browser // {}) |
      .browser.profiles = (.browser.profiles // {}) |
      .browser.profiles.user = {
        "cdpUrl": ("http://127.0.0.1:" + $port),
        "userDataDir": $dir,
        "driver": "existing-session"
      }
    ' "$OPENCLAW_CONFIG" > "$TEMP_CONFIG"
    mv "$TEMP_CONFIG" "$OPENCLAW_CONFIG"
    success "Updated openclaw.json with CDP configuration"
  else
    warn "jq not found. Please manually add to $OPENCLAW_CONFIG:"
    echo -e "${BLUE}  \"browser\": {"
    echo -e "    \"profiles\": {"
    echo -e "      \"user\": {"
    echo -e "        \"cdpUrl\": \"http://127.0.0.1:${CDP_PORT}\","
    echo -e "        \"userDataDir\": \"${CDP_DATA_DIR}\","
    echo -e "        \"driver\": \"existing-session\""
    echo -e "      }"
    echo -e "    }"
    echo -e "  }${NC}"
  fi
else
  warn "openclaw.json not found at $OPENCLAW_CONFIG"
  warn "Create it or add CDP config manually."
fi

# --- Step 11: Summary ---
echo ""
echo -e "${GREEN}════════════════════════════════════════${NC}"
echo -e "${GREEN}  Chrome CDP Setup Complete! 🎉${NC}"
echo -e "${GREEN}════════════════════════════════════════${NC}"
echo ""
echo -e "  CDP URL:     ${BLUE}http://127.0.0.1:${CDP_PORT}${NC}"
echo -e "  Data Dir:    ${BLUE}${CDP_DATA_DIR}${NC}"
echo -e "  Profile:     Symlinked to original (login state preserved)"
if [[ "$OS_TYPE" == "macos" ]]; then
  echo -e "  Auto-start:  LaunchAgent (com.openclaw.chrome-cdp)"
else
  echo -e "  Auto-start:  systemd user service (chrome-cdp)"
fi
if [[ "$PROXY_DETECTED" == "true" ]]; then
  echo ""
  echo -e "  ${YELLOW}⚠ Proxy detected — run: bash scripts/patch-ssrf.sh${NC}"
fi
echo ""
echo -e "  Verify anytime: ${BLUE}bash scripts/verify.sh${NC}"
echo ""
