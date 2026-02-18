#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════
# 🦞 OpenClaw Docker Entrypoint
# ═══════════════════════════════════════════════════════════════════
# Runs on every container start. On first boot, configures:
# - openclaw.json (gateway, models, tools)
# - Gateway authentication token (for UI dashboard access)
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

  cat > "$STATE_DIR/openclaw.json" <<'JSON'
{
  "gateway": {
    "mode": "local",
    "bind": "0.0.0.0"
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
  echo ""
  echo "  ╔══════════════════════════════════════════════════════════╗"
  echo "  ║  🔑 Gateway Token (save this for UI dashboard access):  ║"
  echo "  ╚══════════════════════════════════════════════════════════╝"
  echo "  $GW_TOKEN"
  echo ""

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
