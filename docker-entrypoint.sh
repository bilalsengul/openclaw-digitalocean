#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════
# 🦞 OpenClaw Docker Entrypoint
# ═══════════════════════════════════════════════════════════════════
# Runs on every container start. On first boot, configures:
# - openclaw.json (gateway, models, tools, channels)
# - Gateway authentication token
# - Telegram channel (if TELEGRAM_BOT_TOKEN is set)
# - Exec allowlist for skill scripts
#
# On subsequent starts, only syncs skills and data from the image.
# ═══════════════════════════════════════════════════════════════════
set -euo pipefail

STATE_DIR="$HOME/.openclaw"
APP_DIR="/app"

# ── 1. First-run: generate openclaw.json ─────────────────────────
if [ ! -f "$STATE_DIR/openclaw.json" ]; then
  echo "🔧 First run — generating openclaw.json..."
  mkdir -p "$STATE_DIR"

  cat > "$STATE_DIR/openclaw.json" <<'JSON'
{
  "gateway": {
    "mode": "local"
  },
  "plugins": {
    "enabled": true,
    "entries": {
      "telegram": { "enabled": true }
    }
  },
  "models": {
    "mode": "merge",
    "providers": {}
  },
  "agents": {
    "defaults": {
      "model": {}
    },
    "list": []
  },
  "tools": {
    "exec": {
      "security": "allowlist"
    }
  }
}
JSON

  # ── Generate gateway auth token ────────────────────────────────
  # SECURITY: This prevents unauthorized access to the gateway API.
  GW_TOKEN=$(head -c 32 /dev/urandom | base64 | tr -d '=/+' | head -c 32)
  jq --arg t "$GW_TOKEN" '.gateway.auth.token = $t | .gateway.auth.mode = "token"' \
    "$STATE_DIR/openclaw.json" > "$STATE_DIR/openclaw.json.tmp" \
    && mv "$STATE_DIR/openclaw.json.tmp" "$STATE_DIR/openclaw.json"
  echo "  ✓ Gateway token generated"

  # ── Configure Telegram (if token provided) ─────────────────────
  if [ -n "${TELEGRAM_BOT_TOKEN:-}" ]; then
    # Build allowFrom list
    if [ -n "${TELEGRAM_ALLOWED_IDS:-}" ]; then
      ALLOW_FROM=$(echo "$TELEGRAM_ALLOWED_IDS" | tr ',' '\n' | jq -R . | jq -s .)
    else
      echo "  ⚠️  TELEGRAM_ALLOWED_IDS not set — bot is open to ALL users"
      ALLOW_FROM='["*"]'
    fi

    jq --arg token "$TELEGRAM_BOT_TOKEN" --argjson allow "$ALLOW_FROM" \
      '.channels.telegram.enabled = true
       | .channels.telegram.botToken = $token
       | .channels.telegram.dmPolicy = "pairing"
       | .channels.telegram.allowFrom = $allow' \
      "$STATE_DIR/openclaw.json" > "$STATE_DIR/openclaw.json.tmp" \
      && mv "$STATE_DIR/openclaw.json.tmp" "$STATE_DIR/openclaw.json"
    echo "  ✓ Telegram configured"
  fi

  # ── Let OpenClaw apply auto-detected fixes ─────────────────────
  openclaw doctor --fix 2>/dev/null || true

  # ── Configure exec allowlist ───────────────────────────────────
  # SECURITY: Only allow specific scripts, not arbitrary commands.
  # Add your skill script patterns here:
  for pattern in \
    "python3 /app/skills/*/scripts/*.py *" \
    "python3 /root/.openclaw/skills/*/scripts/*.py *" \
    "cat" "ls" "head" "tail"; do
    openclaw approvals allowlist add --target local --agent '*' --pattern "$pattern" 2>/dev/null || true
  done

  echo "  ✓ openclaw.json created"
fi

# ── 2. Always: sync skills and data ─────────────────────────────
echo "📋 Syncing skills and data..."

# Copy skills from image to OpenClaw managed directory
MANAGED_SKILLS_DIR="$STATE_DIR/skills"
mkdir -p "$MANAGED_SKILLS_DIR"

if [ -d "$APP_DIR/skills" ]; then
  for skill_dir in "$APP_DIR/skills"/*/; do
    skill_name=$(basename "$skill_dir")
    rm -rf "${MANAGED_SKILLS_DIR:?}/${skill_name:?}"
    cp -r "$skill_dir" "$MANAGED_SKILLS_DIR/$skill_name"
  done
  echo "  ✓ Skills synced"
fi

# Copy data/workspace files if present
if [ -d "$APP_DIR/data" ]; then
  mkdir -p "$STATE_DIR/workspace"
  cp -r "$APP_DIR/data/"* "$STATE_DIR/workspace/" 2>/dev/null || true
  echo "  ✓ Workspace data synced"
fi

# ── 3. Hand off to CMD ──────────────────────────────────────────
echo "🚀 Starting OpenClaw..."
exec "$@"
