#!/usr/bin/env bash
set -euo pipefail

# Patch OpenClaw SSRF filter for proxy software (Surge/Clash)
# Allows RFC 2544 benchmarking range (198.18.x.x) used by proxy DNS

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info()    { echo -e "${BLUE}[INFO]${NC} $*"; }
success() { echo -e "${GREEN}[✓]${NC} $*"; }
warn()    { echo -e "${YELLOW}[!]${NC} $*"; }
error()   { echo -e "${RED}[✗]${NC} $*"; exit 1; }

# --- Step 1: Detect proxy environment ---
info "Checking for proxy DNS (198.18.x.x range)..."
TEST_IP=""
if command -v dig &>/dev/null; then
  TEST_IP=$(dig +short google.com 2>/dev/null | head -1)
elif command -v nslookup &>/dev/null; then
  TEST_IP=$(nslookup google.com 2>/dev/null | awk '/^Address: / { print $2 }' | tail -1)
elif command -v host &>/dev/null; then
  TEST_IP=$(host google.com 2>/dev/null | awk '/has address/ { print $4 }' | head -1)
fi

if [[ "$TEST_IP" == 198.18.* ]]; then
  success "Proxy detected: google.com resolves to $TEST_IP"
  info "This is RFC 2544 range used by Surge/Clash virtual IP mode."
else
  warn "DNS resolves to $TEST_IP (not 198.18.x.x)"
  echo -e "${YELLOW}No proxy SSRF conflict detected. Continue anyway? [y/N]${NC}"
  read -r REPLY
  [[ "$REPLY" =~ ^[Yy]$ ]] || exit 0
fi

# --- Step 2: Find OpenClaw SSRF file ---
info "Locating OpenClaw SSRF filter..."
SSRF_FILE=""

# Search common locations
for candidate in \
  /opt/homebrew/lib/node_modules/openclaw \
  /usr/local/lib/node_modules/openclaw \
  /usr/lib/node_modules/openclaw \
  "$HOME/.npm-global/lib/node_modules/openclaw"; do
  if [[ -d "$candidate" ]]; then
    FOUND=$(find "$candidate" -name "ssrf-*.js" -path "*/chunks/*" 2>/dev/null | head -1)
    if [[ -n "$FOUND" ]]; then
      SSRF_FILE="$FOUND"
      break
    fi
  fi
done

# Fallback: use npm root
if [[ -z "$SSRF_FILE" ]]; then
  NPM_ROOT=$(npm root -g 2>/dev/null || echo "")
  if [[ -n "$NPM_ROOT" && -d "$NPM_ROOT/openclaw" ]]; then
    FOUND=$(find "$NPM_ROOT/openclaw" -name "ssrf-*.js" -path "*/chunks/*" 2>/dev/null | head -1)
    [[ -n "$FOUND" ]] && SSRF_FILE="$FOUND"
  fi
fi

[[ -z "$SSRF_FILE" ]] && error "Could not find OpenClaw SSRF filter file (ssrf-*.js). Is OpenClaw installed?"
success "Found: $SSRF_FILE"

# Verify the file contains the target pattern
if ! grep -q 'allowRfc2544BenchmarkRange === true' "$SSRF_FILE"; then
  if grep -q 'allowRfc2544BenchmarkRange !== false' "$SSRF_FILE"; then
    success "SSRF file already patched. Nothing to do."
    exit 0
  fi
  error "Target pattern not found in $SSRF_FILE. File format may have changed."
fi

# --- Step 3: Backup original ---
info "Backing up original file..."
BACKUP="${SSRF_FILE}.bak.$(date +%Y%m%d%H%M%S)"
cp "$SSRF_FILE" "$BACKUP"
success "Backup: $BACKUP"

# --- Step 4: Apply patch ---
info "Patching SSRF filter..."
sed -i.tmp 's/allowRfc2544BenchmarkRange === true/allowRfc2544BenchmarkRange !== false/g' "$SSRF_FILE"
rm -f "${SSRF_FILE}.tmp"

# Verify patch applied
if grep -q 'allowRfc2544BenchmarkRange !== false' "$SSRF_FILE"; then
  success "Patch applied successfully"
else
  error "Patch verification failed. Restoring backup..."
  cp "$BACKUP" "$SSRF_FILE"
  error "Patch failed. Original restored."
fi

# --- Step 5: Remind to restart ---
echo ""
echo -e "${GREEN}════════════════════════════════════════${NC}"
echo -e "${GREEN}  SSRF Patch Applied ✓${NC}"
echo -e "${GREEN}════════════════════════════════════════${NC}"
echo ""
echo -e "  ${YELLOW}⚠ Restart OpenClaw gateway to apply:${NC}"
echo -e "  ${BLUE}openclaw gateway restart${NC}"
echo ""
echo -e "  ${YELLOW}⚠ After OpenClaw updates, re-run this script:${NC}"
echo -e "  ${BLUE}bash scripts/patch-ssrf.sh${NC}"
echo ""
echo -e "  Backup saved: $BACKUP"
echo ""
