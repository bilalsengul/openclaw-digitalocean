#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════
# 🦞 OpenClaw — Deploy Custom Project to DigitalOcean Droplet
# ═══════════════════════════════════════════════════════════════════
#
# A security-hardened installer for custom OpenClaw projects.
# For vanilla OpenClaw, consider the DO 1-Click instead:
#   https://marketplace.digitalocean.com/apps/openclaw
#
# Preconditions:
#   1. You have filled out .env (see example.env)
#   2. doctl is installed (https://docs.digitalocean.com/reference/doctl/how-to/install/)
#
# Usage:
#   bash install.sh              # create Droplet and deploy (interactive)
#   bash install.sh --dry-run    # validate .env without creating resources
#   bash install.sh --update     # update an existing Droplet
#
# Non-interactive (for AI agents):
#   DROPLET_REGION=fra1 DROPLET_SSH_KEY_IDS=12345 bash install.sh
#
# ═══════════════════════════════════════════════════════════════════
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ENV_FILE="$SCRIPT_DIR/.env"

# ── Defaults (override via .env or environment) ─────────────────
PROJECT_NAME="${PROJECT_NAME:-openclaw}"
PROJECT_REPO="${PROJECT_REPO:-}"
REMOTE_DIR="${REMOTE_DIR:-/opt/openclaw}"
DROPLET_SIZE="${DROPLET_SIZE:-s-2vcpu-4gb}"
DROPLET_IMAGE="${DROPLET_IMAGE:-docker-20-04}"

DRY_RUN=false
UPDATE_ONLY=false

# ── Parse arguments ──────────────────────────────────────────────
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=true ;;
    --update) UPDATE_ONLY=true ;;
  esac
done

# ── Helpers ──────────────────────────────────────────────────────
info()  { echo "  $1"; }
ok()    { echo "  ✓ $1"; }
warn()  { echo "  ⚠ $1"; }
fail()  { echo "  ✗ $1" >&2; exit 1; }

# ── 1. Validate .env ────────────────────────────────────────────
echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║  🦞 OpenClaw — Deploy to DigitalOcean                    ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""
echo "[1/7] Validating .env..."

if [ ! -f "$ENV_FILE" ]; then
  fail ".env not found. Run: cp example.env .env"
fi

# Source env file (safely — set -a exports all, set +a stops)
set -a
# shellcheck source=/dev/null
source "$ENV_FILE"
set +a

# Minimum required: DO_API_TOKEN for Droplet management
REQUIRED_VARS=(DO_API_TOKEN PROJECT_NAME PROJECT_REPO)
MISSING=()
for var in "${REQUIRED_VARS[@]}"; do
  if [ -z "${!var:-}" ]; then
    MISSING+=("$var")
  fi
done

if [ ${#MISSING[@]} -gt 0 ]; then
  echo "  Missing required variables in .env:"
  for var in "${MISSING[@]}"; do
    echo "    - $var"
  done
  fail "Fill in these values in .env and try again."
fi
ok "All required variables set"

if $DRY_RUN; then
  echo ""
  echo "✅ Dry run passed — .env is valid."
  echo "   Run without --dry-run to deploy."
  exit 0
fi

# ── 2. Check doctl ──────────────────────────────────────────────
echo ""
echo "[2/7] Checking doctl..."

if ! command -v doctl &>/dev/null; then
  echo "  doctl is not installed."
  echo ""
  echo "  Install it:"
  echo "    macOS:  brew install doctl"
  echo "    Linux:  snap install doctl"
  echo "    Other:  https://docs.digitalocean.com/reference/doctl/how-to/install/"
  fail "Install doctl and try again."
fi
ok "doctl found"

# ── 3. Authenticate with DigitalOcean ───────────────────────────
echo ""
echo "[3/7] Authenticating with DigitalOcean..."

doctl auth init -t "$DO_API_TOKEN" 2>/dev/null
ok "Authenticated"

# ── Helper: SSH with retries (handles sshd restarts) ────────────
SSH_OPTS=(-o StrictHostKeyChecking=accept-new -o ConnectTimeout=10)

remote_cmd() {
  local droplet_ip="$1"; shift
  for _attempt in 1 2 3; do
    if ssh "${SSH_OPTS[@]}" "root@$droplet_ip" "$@" 2>/dev/null; then
      return 0
    fi
    sleep 5
  done
  ssh "${SSH_OPTS[@]}" "root@$droplet_ip" "$@"  # final attempt — let errors through
}

wait_for_ssh() {
  local droplet_ip="$1"
  info "Waiting for SSH to become available..."
  for _i in $(seq 1 30); do
    if ssh "${SSH_OPTS[@]}" "root@$droplet_ip" true 2>/dev/null; then
      return 0
    fi
    sleep 5
  done
  fail "SSH connection timed out after 150s"
}

# ═══════════════════════════════════════════════════════════════════
# UPDATE MODE — update an existing Droplet
# ═══════════════════════════════════════════════════════════════════
if $UPDATE_ONLY; then
  echo ""
  echo "[4/7] Updating existing Droplet..."

  DROPLET_IP=$(doctl compute droplet list --format Name,PublicIPv4 --no-header | grep "^$PROJECT_NAME" | awk '{print $2}' || true)
  if [ -z "$DROPLET_IP" ]; then
    fail "Droplet '$PROJECT_NAME' not found. Run without --update to create it."
  fi
  ok "Found Droplet at $DROPLET_IP"

  echo ""
  echo "[5/7] Deploying update..."
  scp "${SSH_OPTS[@]}" "$ENV_FILE" "root@$DROPLET_IP:$REMOTE_DIR/.env"
  remote_cmd "$DROPLET_IP" "chmod 600 $REMOTE_DIR/.env && cd $REMOTE_DIR && git pull origin main && docker compose up -d --build"
  ok "Update deployed"

  echo ""
  echo "[6/7] Verifying..."
  sleep 5
  if remote_cmd "$DROPLET_IP" "docker ps --filter name=$PROJECT_NAME --format '{{.Status}}'" | grep -q "Up"; then
    echo ""
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║  ✅ Update deployed successfully!                        ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo ""
    echo "  SSH:   ssh root@$DROPLET_IP"
    echo "  Logs:  ssh root@$DROPLET_IP docker logs -f $PROJECT_NAME"
  else
    echo "⚠️  Container may not be healthy. Check:"
    echo "   ssh root@$DROPLET_IP docker logs $PROJECT_NAME"
  fi
  exit 0
fi

# ═══════════════════════════════════════════════════════════════════
# FRESH DEPLOY — create a new Droplet
# ═══════════════════════════════════════════════════════════════════
echo ""
echo "[4/7] Creating Droplet..."

# Check if Droplet already exists
EXISTING_IP=$(doctl compute droplet list --format Name,PublicIPv4 --no-header | grep "^$PROJECT_NAME" | awk '{print $2}' || true)
if [ -n "$EXISTING_IP" ]; then
  echo "  Droplet '$PROJECT_NAME' already exists at $EXISTING_IP"
  echo "  Use --update to deploy changes, or delete and re-run."
  fail "Droplet already exists."
fi

# Pick region (env var or interactive)
if [ -n "${DROPLET_REGION:-}" ]; then
  REGION="$DROPLET_REGION"
  ok "Region: $REGION (from DROPLET_REGION)"
else
  echo "  Available regions: nyc1 nyc3 sfo3 ams3 lon1 fra1 sgp1 blr1 tor1"
  read -rp "  Region [fra1]: " REGION
  REGION="${REGION:-fra1}"
fi

# SSH key (env var or interactive)
SSH_KEYS=$(doctl compute ssh-key list --format ID,Name --no-header)
if [ -z "$SSH_KEYS" ]; then
  echo "  No SSH keys found in your DO account."
  echo "  Add one: doctl compute ssh-key import my-key --public-key-file ~/.ssh/id_rsa.pub"
  fail "Add an SSH key to DigitalOcean and try again."
fi

if [ -n "${DROPLET_SSH_KEY_IDS:-}" ]; then
  SSH_KEY_ID="$DROPLET_SSH_KEY_IDS"
  ok "SSH keys: $SSH_KEY_ID (from DROPLET_SSH_KEY_IDS)"
else
  echo "  Your SSH keys:"
  echo "$SSH_KEYS" | while IFS= read -r line; do echo "    $line"; done
  read -rp "  SSH key ID(s) to use (comma-separated): " SSH_KEY_ID
fi

info "Creating $PROJECT_NAME ($DROPLET_SIZE in $REGION)..."
doctl compute droplet create "$PROJECT_NAME" \
  --image "$DROPLET_IMAGE" \
  --size "$DROPLET_SIZE" \
  --region "$REGION" \
  --ssh-keys "$SSH_KEY_ID" \
  --wait

DROPLET_IP=$(doctl compute droplet get "$PROJECT_NAME" --format PublicIPv4 --no-header)
ok "Droplet created at $DROPLET_IP"

# ── 5. Wait for SSH + cloud-init ────────────────────────────────
echo ""
echo "[5/7] Preparing Droplet..."

wait_for_ssh "$DROPLET_IP"
ok "SSH connected"

# Wait for cloud-init to finish (sshd may restart during init)
info "Waiting for cloud-init to finish..."
remote_cmd "$DROPLET_IP" 'cloud-init status --wait > /dev/null 2>&1 || sleep 10'
ok "Droplet ready"

# ── 6. Security hardening ───────────────────────────────────────
echo ""
echo "[6/7] Hardening Droplet..."

# 6a. Firewall — deny all incoming, rate-limit SSH
info "Configuring firewall..."
remote_cmd "$DROPLET_IP" 'ufw default deny incoming && ufw default allow outgoing && ufw limit ssh/tcp comment "SSH (rate-limited)" && ufw allow 80/tcp comment "HTTP" && ufw allow 443/tcp comment "HTTPS" && ufw delete allow 2375/tcp 2>/dev/null; ufw delete allow 2376/tcp 2>/dev/null; ufw --force enable'
ok "Firewall active (SSH rate-limited, HTTP/HTTPS allowed)"

# 6b. Fail2ban — brute-force protection
info "Installing fail2ban..."
if remote_cmd "$DROPLET_IP" 'apt-get install -y -qq fail2ban > /dev/null 2>&1 && systemctl enable fail2ban && systemctl start fail2ban' 2>/dev/null; then
  ok "Fail2ban active"
else
  warn "Fail2ban install skipped (apt may be locked). Install manually later."
fi

# 6c. Unattended security upgrades
info "Enabling automatic security updates..."
if remote_cmd "$DROPLET_IP" 'apt-get install -y -qq unattended-upgrades > /dev/null 2>&1 && dpkg-reconfigure -f noninteractive unattended-upgrades' 2>/dev/null; then
  ok "Unattended-upgrades enabled"
else
  warn "Unattended-upgrades skipped (apt may be locked). Install manually later."
fi

# 6d. SSH hardening — enforce key-only auth (no passwords)
info "Hardening SSH..."
remote_cmd "$DROPLET_IP" 'sed -i "s/^#*PasswordAuthentication .*/PasswordAuthentication no/" /etc/ssh/sshd_config && sed -i "s/^#*PermitRootLogin .*/PermitRootLogin prohibit-password/" /etc/ssh/sshd_config && systemctl reload sshd'
ok "SSH hardened (key-only, no password auth)"

# 6e. Docker log rotation — prevent disk fill
info "Configuring Docker log rotation..."
remote_cmd "$DROPLET_IP" 'mkdir -p /etc/docker && cat > /etc/docker/daemon.json << EOF
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  }
}
EOF
systemctl restart docker'
ok "Docker log rotation configured (10MB × 3 files)"

# 6f. Custom MOTD — lobster greeting on SSH login
info "Installing lobster MOTD..."
remote_cmd "$DROPLET_IP" 'cat > /etc/update-motd.d/99-openclaw << '\''MOTD'\''
#!/bin/bash
QUOTES=(
  "The ocean floor is just another frontier."
  "Even the strongest shell started as a soft molt."
  "Claws up, bugs down."
  "I did not crawl out of the primordial ooze to write YAML by hand."
  "Every great deploy starts with a single pinch."
  "Trust the current, but verify the config."
  "In deep water, nobody hears you segfault."
  "Born to pinch. Forced to parse JSON."
  "My shell is hardened. Is yours?"
  "Keep your claws sharp and your tokens secret."
)
QUOTE=${QUOTES[$((RANDOM % ${#QUOTES[@]}))]}

echo ""
echo "  🦞 OpenClaw — Pioneer Lobster Edition"
echo "  ──────────────────────────────────────"
echo "  \"$QUOTE\""
echo ""
echo "  Dashboard: https://$(hostname -I | awk '\''{print $1}'\'')"
echo "  Logs:      docker logs -f $(cat /etc/hostname 2>/dev/null || echo openclaw)"
echo "  Status:    docker ps"
echo ""
MOTD
chmod +x /etc/update-motd.d/99-openclaw'
ok "Lobster MOTD installed"

# ── 7. Configure Caddy (Host-based for valid IP SSL) ────────────────
info "Installing & configuring Caddy (host-based)..."
remote_cmd "$DROPLET_IP" "apt-get update && apt-get install -y debian-keyring debian-archive-keyring apt-transport-https curl && curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg && curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | tee /etc/apt/sources.list.d/caddy-stable.list && apt-get update && apt-get install -y caddy"

# Configure Caddyfile with explicit ACME issuer for IP
remote_cmd "$DROPLET_IP" "cat > /etc/caddy/Caddyfile <<EOF
$DROPLET_IP {
    tls {
        issuer acme {
            dir https://acme-v02.api.letsencrypt.org/directory
            profile shortlived
        }
    }
    reverse_proxy localhost:18789
}
EOF
systemctl restart caddy"
ok "Caddy installed and configured on host"

# ── 8. Deploy application ──────────────────────────────────────
echo ""
echo "[8/8] Deploying application..."

# Clone repo
info "Cloning repository..."
remote_cmd "$DROPLET_IP" "git clone $PROJECT_REPO $REMOTE_DIR 2>/dev/null || (cd $REMOTE_DIR && git pull origin main)"

# Upload .env (secure permissions)
info "Uploading .env..."
scp "${SSH_OPTS[@]}" "$ENV_FILE" "root@$DROPLET_IP:$REMOTE_DIR/.env"
remote_cmd "$DROPLET_IP" "chmod 600 $REMOTE_DIR/.env"

# Build and start ONLY OpenClaw (Caddy is managed on host now)
info "Starting Docker containers..."
remote_cmd "$DROPLET_IP" "cd $REMOTE_DIR && docker compose up -d --build openclaw"
ok "Containers started"

# ── Verify ──────────────────────────────────────────────────────
echo ""
echo "  Waiting for container to stabilize..."
sleep 10

if remote_cmd "$DROPLET_IP" "docker ps --filter name=$PROJECT_NAME --format '{{.Status}}'" | grep -q "Up"; then
  echo ""
  # Retrieve gateway token for display
  GW_TOKEN=$(remote_cmd "$DROPLET_IP" "docker exec $PROJECT_NAME cat /home/openclaw/.openclaw/openclaw.json 2>/dev/null | jq -r '.gateway.auth.token // empty'" 2>/dev/null || true)

  echo "╔════════════════════════════════════════════════════════════╗"
  echo "║  🦞 OpenClaw is running!                                 ║"
  echo "╚════════════════════════════════════════════════════════════╝"
  echo ""
  echo "  Droplet IP:  $DROPLET_IP"
  echo "  SSH access:  ssh root@$DROPLET_IP"
  echo "  View logs:   ssh root@$DROPLET_IP docker logs -f $PROJECT_NAME"
  echo "  Update:      bash install.sh --update"
  echo ""
  echo "  🔒 Security hardening applied:"
  echo "     • UFW firewall (SSH rate-limited, HTTP/HTTPS allowed)"
  echo "     • Fail2ban (SSH brute-force protection)"
  echo "     • Unattended security upgrades"
  echo "     • SSH key-only authentication"
  echo "     • Docker log rotation"
  echo "     • .env file permissions (600)"
  echo ""
  echo "  🌐 NEXT STEP: Pair your browser with the dashboard."
  echo ""
  echo "     URL:   https://$DROPLET_IP"
  if [ -n "${GW_TOKEN:-}" ]; then
    echo "     Token: $GW_TOKEN"
  else
    echo "     Token: (check container logs or ssh into the Droplet)"
  fi
  echo ""
  echo "     1. Open the URL above in your browser"
  echo "     2. Open the Overview panel in the sidebar"
  echo "     3. Paste the gateway token and click Connect"
  echo "     4. You'll see a 'pairing required' error — this is expected"
  echo ""

  # ── Automated pairing ──────────────────────────────────────────
  if [ -n "${GW_TOKEN:-}" ]; then
    read -rp "  Press Enter once you see the 'pairing required' error (or 'q' to skip): " PAIR_REPLY
    if [ "${PAIR_REPLY:-}" != "q" ]; then
      echo ""
      echo "  🔍 Looking for pending pairing requests..."

      # List pending device requests via the CLI
      PENDING=$(remote_cmd "$DROPLET_IP" "docker exec $PROJECT_NAME openclaw devices list --token=$GW_TOKEN 2>/dev/null" || true)
      # Extract request IDs (UUIDs from the pending section)
      REQUEST_IDS=$(echo "$PENDING" | grep -oE '[a-f0-9]{8}-([a-f0-9]{4}-){3}[a-f0-9]{12}' || true)
      COUNT=$(echo "$REQUEST_IDS" | grep -c . 2>/dev/null || echo 0)

      if [ "$COUNT" -eq 1 ]; then
        REQ_ID=$(echo "$REQUEST_IDS" | head -1)
        echo "  ✅ Found pairing request: $REQ_ID"
        echo "     Approving..."
        remote_cmd "$DROPLET_IP" "docker exec $PROJECT_NAME openclaw devices approve $REQ_ID --token=$GW_TOKEN 2>/dev/null" || true
        echo ""
        echo "  ╔════════════════════════════════════════════════════════════╗"
        echo "  ║  🎉 Pairing approved! Refresh the dashboard to begin.    ║"
        echo "  ╚════════════════════════════════════════════════════════════╝"
      elif [ "$COUNT" -eq 0 ]; then
        echo "  ⚠️  No pending requests found. Make sure you've opened the dashboard"
        echo "     and connected with the gateway token first."
        echo ""
        echo "  To approve manually later:"
        echo "    ssh root@$DROPLET_IP docker exec $PROJECT_NAME openclaw devices list --token=\$TOKEN"
        echo "    ssh root@$DROPLET_IP docker exec $PROJECT_NAME openclaw devices approve \$REQUEST_ID --token=\$TOKEN"
      else
        echo "  ⚠️  Multiple pending requests found ($COUNT). Approve manually:"
        echo "    ssh root@$DROPLET_IP docker exec $PROJECT_NAME openclaw devices list --token=\$TOKEN"
        echo "    ssh root@$DROPLET_IP docker exec $PROJECT_NAME openclaw devices approve \$REQUEST_ID --token=\$TOKEN"
      fi
    fi
  fi
  echo ""
else
  echo "⚠️  Container may not be healthy yet. Check:"
  echo "   ssh root@$DROPLET_IP docker logs $PROJECT_NAME"
fi
