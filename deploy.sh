#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════
# 🦞 OpenClaw — Deploy Updates (run on the Droplet)
# ═══════════════════════════════════════════════════════════════════
# Run this ON the Droplet to pull the latest code and restart.
#
# Usage:
#   cd /opt/openclaw && bash deploy.sh
#
# For remote deploys from your local machine, use:
#   bash install.sh --update
# ═══════════════════════════════════════════════════════════════════
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_NAME="${PROJECT_NAME:-openclaw}"

echo "Pulling latest changes..."
git -C "$SCRIPT_DIR" pull origin main

echo "Rebuilding and restarting containers..."
cd "$SCRIPT_DIR"
docker compose up -d --build --remove-orphans

sleep 5
if docker ps --filter "name=$PROJECT_NAME" --format '{{.Status}}' | grep -q "Up"; then
  echo "✅ OpenClaw updated and running"
  echo "   View logs: docker logs -f $PROJECT_NAME"
else
  echo "⚠️  Container may not be healthy. Check: docker logs $PROJECT_NAME"
fi
