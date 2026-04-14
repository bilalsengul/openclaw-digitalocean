#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════
# 🦞 OpenClaw Docker Entrypoint
# ═══════════════════════════════════════════════════════════════════
# Runs on every container start. On first boot, configures:
# - openclaw.json (gateway, models, tools)
# - Gateway authentication token (printed to logs for agent to read)
# - Exec allowlist for skill scripts
#
# Configure messaging channels (Telegram, WhatsApp, etc.) via the
# OpenClaw UI dashboard after deployment.
#
# On subsequent starts, only syncs skills and data from the image.
# ═══════════════════════════════════════════════════════════════════
set -euo pipefail

STATE_DIR="/home/openclaw/.openclaw"
APP_DIR="/app"

# ── 1. First-run: generate openclaw.json ─────────────────────────
if [ ! -f "$STATE_DIR/openclaw.json" ]; then
  echo "🔧 First run — generating openclaw.json..."
  mkdir -p "$STATE_DIR"
  mkdir -p "$STATE_DIR/agents/main/sessions"
  mkdir -p "$STATE_DIR/credentials"
  chmod 700 "$STATE_DIR"

  cat > "$STATE_DIR/openclaw.json" <<'JSON'
{
  "gateway": {
    "mode": "local",
    "bind": "custom",
    "customBindHost": "0.0.0.0",
    "controlUi": {
      "allowInsecureAuth": true,
      "dangerouslyDisableDeviceAuth": true,
      "dangerouslyAllowHostHeaderOriginFallback": true
    },
    "trustedProxies": [
      "172.16.0.0/12",
      "10.0.0.0/8",
      "127.0.0.1"
    ]
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

  # ── Gradient AI provider (conditional) ─────────────────────────
  # If GRADIENT_API_KEY is set, inject the full model catalog from
  # /etc/openclaw/gradient-provider.json (29 models, all providers).
  # This MUST run BEFORE `openclaw doctor --fix` so the doctor
  # validates the complete config (not just the skeleton).
  if [ -n "${GRADIENT_API_KEY:-}" ]; then
    echo "  🔧 Configuring Gradient AI provider..."
    jq --arg key "$GRADIENT_API_KEY" \
       --slurpfile gp /etc/openclaw/gradient-provider.json \
       '. * $gp[0] | .models.providers.gradient.apiKey = $key' \
       "$STATE_DIR/openclaw.json" > "$STATE_DIR/openclaw.json.tmp" \
       && mv "$STATE_DIR/openclaw.json.tmp" "$STATE_DIR/openclaw.json"
    echo "  ✓ Gradient AI configured (29 models, default: openai-gpt-oss-120b)"
  else
    echo "  ℹ️  GRADIENT_API_KEY not set — configure a model provider via the UI"
  fi

  # ── Generate gateway auth token (BEFORE doctor) ────────────────
  GW_TOKEN=$(head -c 32 /dev/urandom | base64 | tr -d '=/+' | head -c 32)
  jq --arg t "$GW_TOKEN" '.gateway.auth.token = $t | .gateway.auth.mode = "token"' \
    "$STATE_DIR/openclaw.json" > "$STATE_DIR/openclaw.json.tmp" \
    && mv "$STATE_DIR/openclaw.json.tmp" "$STATE_DIR/openclaw.json"
  echo "  ✓ Gateway token generated"
  echo ""
  echo "  OPENCLAW_GATEWAY_TOKEN=$GW_TOKEN"
  echo ""

  # ── Fix file permissions before doctor ─────────────────────────
  chmod 600 "$STATE_DIR/openclaw.json"

  # ── Let OpenClaw apply auto-detected fixes ─────────────────────
  openclaw doctor --fix 2>/dev/null || true

  # ── Configure exec allowlist ───────────────────────────────────
  # SECURITY: Only allow specific scripts, not arbitrary commands.
  # Add your skill script patterns here:
  for pattern in \
    "python3 /app/skills/*/scripts/*.py *" \
    "python3 /home/openclaw/.openclaw/skills/*/scripts/*.py *" \
    "cat" "ls" "head" "tail"; do
    openclaw approvals allowlist add --target local --agent '*' --pattern "$pattern" 2>/dev/null || true
  done

  echo "  ✓ openclaw.json created"
fi

# ── 1b. Always: configure channels from env vars ────────────────
# Patches openclaw.json with Discord and WhatsApp config on every
# start, so env var changes take effect without wiping the volume.

CONFIG="$STATE_DIR/openclaw.json"

# ── Discord channel ──────────────────────────────────────────────
if [ -n "${DISCORD_BOT_TOKEN:-}" ]; then
  echo "  🔧 Configuring Discord channel..."
  jq '.channels.discord = {
    "enabled": true,
    "token": { "source": "env", "provider": "default", "id": "DISCORD_BOT_TOKEN" }
  }' "$CONFIG" > "$CONFIG.tmp" && mv "$CONFIG.tmp" "$CONFIG"
  chmod 600 "$CONFIG"
  echo "  ✓ Discord channel configured"
else
  echo "  ℹ️  DISCORD_BOT_TOKEN not set — skipping Discord"
fi

# ── Telegram channel ─────────────────────────────────────────────
if [ -n "${TELEGRAM_BOT_TOKEN:-}" ]; then
  echo "  🔧 Configuring Telegram channel..."
  jq '.channels.telegram = {
    "enabled": true,
    "botToken": { "source": "env", "provider": "default", "id": "TELEGRAM_BOT_TOKEN" }
  }' "$CONFIG" > "$CONFIG.tmp" && mv "$CONFIG.tmp" "$CONFIG"
  chmod 600 "$CONFIG"
  echo "  ✓ Telegram channel configured"
else
  echo "  ℹ️  TELEGRAM_BOT_TOKEN not set — skipping Telegram"
fi

# ── WhatsApp channel ─────────────────────────────────────────────
if [ "${WHATSAPP_ENABLED:-false}" = "true" ]; then
  echo "  🔧 Configuring WhatsApp channel..."
  ALLOW_FROM="${WHATSAPP_ALLOW_FROM:-}"
  if [ -n "$ALLOW_FROM" ]; then
    # Convert comma-separated numbers to JSON array
    ALLOW_JSON=$(echo "$ALLOW_FROM" | jq -R 'split(",") | map(gsub("\\s"; ""))')
  else
    ALLOW_JSON="[]"
  fi
  jq --argjson allow "$ALLOW_JSON" '.channels.whatsapp = {
    "dmPolicy": "pairing",
    "allowFrom": $allow,
    "groupPolicy": "allowlist",
    "groups": { "*": { "requireMention": true } },
    "sendReadReceipts": true,
    "reactionLevel": "minimal",
    "ackReaction": { "emoji": "👀", "direct": true, "group": "mentions" },
    "mediaMaxMb": 50
  }' "$CONFIG" > "$CONFIG.tmp" && mv "$CONFIG.tmp" "$CONFIG"
  chmod 600 "$CONFIG"
  echo "  ✓ WhatsApp channel configured (pair via Control UI)"
else
  echo "  ℹ️  WHATSAPP_ENABLED not set — skipping WhatsApp"
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
