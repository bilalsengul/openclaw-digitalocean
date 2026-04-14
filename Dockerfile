# ═══════════════════════════════════════════════════════════════════
# 🦞 OpenClaw — Docker Image
# ═══════════════════════════════════════════════════════════════════
# Multi-stage build: Node.js (OpenClaw gateway) + Python (skills)
#
# Build:  docker build -t my-openclaw-project .
# Run:    docker compose up -d
# ═══════════════════════════════════════════════════════════════════

# ── Stage 1: Node.js + OpenClaw ──────────────────────────────────
FROM node:22-slim AS base

# Install git + SSL certs (required by OpenClaw dependencies)
RUN apt-get update -qq && apt-get install -y --no-install-recommends git ca-certificates && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# Create non-root user (matches DO 1-Click's dedicated openclaw user)
RUN useradd -m -s /bin/bash openclaw

# Install pnpm and OpenClaw globally
RUN corepack enable && corepack prepare pnpm@latest --activate
ENV PNPM_HOME="/home/openclaw/.local/share/pnpm"
ENV PATH="$PNPM_HOME:$PATH"
RUN mkdir -p "$PNPM_HOME" && chown -R openclaw:openclaw "$PNPM_HOME"
ARG OPENCLAW_VERSION=2026.2.15
RUN pnpm add -g "openclaw@${OPENCLAW_VERSION}"

# ── Stage 2: Add Python + skill dependencies ────────────────────
FROM base AS runtime

# System packages: Python 3, pip, and build tools for native deps
RUN apt-get update -qq && \
    apt-get install -y --no-install-recommends \
    python3 python3-pip python3-venv build-essential jq curl && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Install Python dependencies (if you have any)
COPY requirements.txt /tmp/requirements.txt
RUN pip3 install --break-system-packages --no-cache-dir -r /tmp/requirements.txt && \
    rm /tmp/requirements.txt

# ── App files ────────────────────────────────────────────────────
WORKDIR /app

# Copy your skills and agent data
# Uncomment / modify these as needed for your project:
# COPY skills/ ./skills/
# COPY data/ ./data/

# ── Entrypoint ───────────────────────────────────────────────────
COPY gradient-provider.json /etc/openclaw/gradient-provider.json
COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

# OpenClaw state directory — mount a volume here for persistence
RUN mkdir -p /home/openclaw/.openclaw && chown openclaw:openclaw /home/openclaw/.openclaw
VOLUME /home/openclaw/.openclaw

EXPOSE 18789

# Run as non-root user
USER openclaw

ENTRYPOINT ["docker-entrypoint.sh"]
CMD ["openclaw", "gateway", "run"]
