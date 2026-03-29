#!/usr/bin/env bash
set -euo pipefail

# Chrome CDP Verify - Full diagnostic report

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

CDP_PORT="${CDP_PORT:-9222}"
CDP_DATA_DIR="$HOME/.chrome-cdp-data"
PASS=0
FAIL=0

check_pass() { echo -e "  ${GREEN}✓${NC} $*"; PASS=$((PASS + 1)); }
check_fail() { echo -e "  ${RED}✗${NC} $*"; FAIL=$((FAIL + 1)); }
check_warn() { echo -e "  ${YELLOW}!${NC} $*"; }

echo -e "${BLUE}═══════════════════════════════════════${NC}"
echo -e "${BLUE}  Chrome CDP Diagnostic Report${NC}"
echo -e "${BLUE}═══════════════════════════════════════${NC}"
echo ""

# --- Check 1: Chrome process ---
echo -e "${BLUE}[1/5] Chrome Process${NC}"
if pgrep -f "remote-debugging-port=${CDP_PORT}" &>/dev/null; then
  PID=$(pgrep -f "remote-debugging-port=${CDP_PORT}" | head -1)
  check_pass "Chrome running with CDP (PID: $PID)"
elif pgrep -f "Google Chrome" &>/dev/null || pgrep -f "google-chrome" &>/dev/null; then
  check_warn "Chrome is running but may not have CDP enabled"
  FAIL=$((FAIL + 1))
else
  check_fail "Chrome is not running"
fi
echo ""

# --- Check 2: Port listening ---
echo -e "${BLUE}[2/5] Port $CDP_PORT${NC}"
if lsof -iTCP:"$CDP_PORT" -sTCP:LISTEN &>/dev/null 2>&1; then
  LISTENER=$(lsof -iTCP:"$CDP_PORT" -sTCP:LISTEN 2>/dev/null | tail -1 | awk '{print $1}')
  check_pass "Port $CDP_PORT is listening ($LISTENER)"
elif command -v ss &>/dev/null && ss -tlnp 2>/dev/null | grep -q ":${CDP_PORT}"; then
  check_pass "Port $CDP_PORT is listening"
else
  check_fail "Nothing listening on port $CDP_PORT"
fi
echo ""

# --- Check 3: CDP endpoint ---
echo -e "${BLUE}[3/5] CDP Endpoint${NC}"
CDP_RESPONSE=$(curl -sf "http://127.0.0.1:${CDP_PORT}/json/version" 2>/dev/null || echo "")
if [[ -n "$CDP_RESPONSE" ]]; then
  BROWSER_VER=$(echo "$CDP_RESPONSE" | grep -o '"Browser":"[^"]*"' | cut -d'"' -f4)
  WS_URL=$(echo "$CDP_RESPONSE" | grep -o '"webSocketDebuggerUrl":"[^"]*"' | cut -d'"' -f4)
  check_pass "CDP responding"
  [[ -n "$BROWSER_VER" ]] && echo -e "       Browser: $BROWSER_VER"
  [[ -n "$WS_URL" ]] && echo -e "       WS URL:  $WS_URL"

  # Also check for open tabs
  TAB_COUNT=$(curl -sf "http://127.0.0.1:${CDP_PORT}/json/list" 2>/dev/null | grep -c '"id"' || echo "0")
  echo -e "       Open tabs: $TAB_COUNT"
else
  check_fail "CDP not responding at http://127.0.0.1:${CDP_PORT}/json/version"
fi
echo ""

# --- Check 4: DevToolsActivePort file ---
echo -e "${BLUE}[4/5] DevToolsActivePort${NC}"
ACTIVE_PORT_FILE="$CDP_DATA_DIR/DevToolsActivePort"
if [[ -f "$ACTIVE_PORT_FILE" ]]; then
  PORT_CONTENT=$(head -1 "$ACTIVE_PORT_FILE")
  check_pass "DevToolsActivePort exists (port: $PORT_CONTENT)"
else
  check_fail "DevToolsActivePort not found at $ACTIVE_PORT_FILE"
  echo -e "       This file is created by Chrome when CDP starts successfully."
fi

# Check symlink
if [[ -L "$CDP_DATA_DIR/Default" ]]; then
  LINK_TARGET=$(readlink "$CDP_DATA_DIR/Default")
  check_pass "Default profile symlink → $LINK_TARGET"
elif [[ -d "$CDP_DATA_DIR/Default" ]]; then
  check_warn "Default is a real directory (not symlinked to original profile)"
else
  check_fail "Default profile directory missing from $CDP_DATA_DIR"
fi
echo ""

# --- Check 5: OpenClaw configuration ---
echo -e "${BLUE}[5/5] OpenClaw Configuration${NC}"
OPENCLAW_CONFIG="$HOME/.openclaw/openclaw.json"
if [[ -f "$OPENCLAW_CONFIG" ]]; then
  if command -v jq &>/dev/null; then
    CDP_URL=$(jq -r '.browser.profiles.user.cdpUrl // empty' "$OPENCLAW_CONFIG" 2>/dev/null)
    DRIVER=$(jq -r '.browser.profiles.user.driver // empty' "$OPENCLAW_CONFIG" 2>/dev/null)
    USER_DIR=$(jq -r '.browser.profiles.user.userDataDir // empty' "$OPENCLAW_CONFIG" 2>/dev/null)

    if [[ "$CDP_URL" == "http://127.0.0.1:${CDP_PORT}" ]]; then
      check_pass "cdpUrl: $CDP_URL"
    elif [[ -n "$CDP_URL" ]]; then
      check_warn "cdpUrl: $CDP_URL (expected http://127.0.0.1:${CDP_PORT})"
    else
      check_fail "cdpUrl not configured in openclaw.json"
    fi

    if [[ "$DRIVER" == "existing-session" ]]; then
      check_pass "driver: existing-session"
    elif [[ -n "$DRIVER" ]]; then
      check_warn "driver: $DRIVER (expected existing-session)"
    else
      check_fail "driver not configured in openclaw.json"
    fi

    if [[ -n "$USER_DIR" ]]; then
      check_pass "userDataDir: $USER_DIR"
    else
      check_fail "userDataDir not configured in openclaw.json"
    fi
  else
    # Fallback: grep for cdpUrl
    if grep -q "127.0.0.1:${CDP_PORT}" "$OPENCLAW_CONFIG" 2>/dev/null; then
      check_pass "CDP URL found in openclaw.json"
    else
      check_fail "CDP URL not found in openclaw.json"
    fi
  fi
else
  check_fail "openclaw.json not found at $OPENCLAW_CONFIG"
fi
echo ""

# --- Summary ---
echo -e "${BLUE}═══════════════════════════════════════${NC}"
if [[ $FAIL -eq 0 ]]; then
  echo -e "  ${GREEN}All checks passed ($PASS/$PASS) ✓${NC}"
else
  echo -e "  ${GREEN}Passed: $PASS${NC}  ${RED}Failed: $FAIL${NC}"
  echo ""
  echo -e "  Run ${BLUE}bash scripts/setup.sh${NC} to fix issues."
fi
echo -e "${BLUE}═══════════════════════════════════════${NC}"

exit $FAIL
