# 🦞 OpenClaw Deployment Scaffold for DigitalOcean

```
                                        THE PIONEER LOBSTER
                                        ━━━━━━━━━━━━━━━━━━━━
          ,__          __,              "Deploy first, grow a shell
           \_.._  _.._/                  later. The cloud is wild,
            /    \/    \   🦞──▶          the AI agents are wilder,
           | (o)  (o)  |       ☁️         and this lobster has
           \   .__.   /      ☁️☁️         claws for both."
            \  `--'  /     ☁️☁️☁️
       __.---`------'  ☁️☁️☁️☁️☁️☁️
  🔒  Security-hardened · Docker-first · Battle-tested by crustaceans
```

> **For vanilla OpenClaw**, use the [DO 1-Click](https://marketplace.digitalocean.com/apps/openclaw) — it's literally one button.
>
> **This scaffold is for custom projects** — when you have your own skills, agents, Python dependencies, and Dockerfile. The Pioneer Lobster went through every gotcha so you wouldn't have to.
>
> Inspired by DigitalOcean's [1-Click Packer scripts](https://github.com/digitalocean/droplet-1-clicks/tree/master/clawdbot-24-04) — we matched their security, Caddy TLS, and pairing UX, then added Docker isolation, Gradient AI integration, and non-interactive deployment.

---

## 🤖 Built for AI Agents (Claude Code, Antigravity, etc.)

**"Finally, a deployment guide that speaks binary."** — *The Pioneer Lobster* 🦞

This repository is designed to be consumed by **AI Coding Agents**. It replaces brittle shell scripts with **AI Runbooks** (`install.md`, `update_deployment.md`) — declarative markdown files that your AI agent can read, understand, and execute step-by-step.

**To deploy:** Simply paste `install.md` into your agent's context and say:
> *"Follow this runbook to deploy to DigitalOcean."*

---

## Prerequisites

Before you begin, you'll need three things from DigitalOcean:

### 1. A DigitalOcean Account + API Token

The installer uses the **DigitalOcean API** to create and manage your Droplet (a cloud VM). You also need **`doctl`** (the DigitalOcean CLI) installed on your local machine — the script uses it to create Droplets, manage SSH keys, and deploy your code.

**How to get your API token:**
1. Sign up or log in at [cloud.digitalocean.com](https://cloud.digitalocean.com)
2. Go to **API** → **Tokens** (left sidebar)
3. Click **Generate New Token**
4. Name it (e.g., "openclaw-deploy"), select **Full Access**, click **Generate**
5. Copy the token immediately — it's only shown once

This token goes in your `.env` as `DO_API_TOKEN`.

### 2. An SSH Key (registered with DigitalOcean)

The installer needs an SSH key to securely access your Droplet. Password authentication is disabled for security.

**If you don't have an SSH key yet:**
```bash
ssh-keygen -t ed25519 -C "your-email@example.com"
# Accept defaults, optionally set a passphrase
```

**Register it with DigitalOcean:**
1. Go to **Settings** → **Security** → **SSH Keys**
2. Click **Add SSH Key**
3. Paste the contents of `~/.ssh/id_ed25519.pub`
4. Note the key's **numeric ID** — the installer will ask for it (or set `DROPLET_SSH_KEY_IDS` in `.env`)

### 3. A Gradient AI API Key (recommended)

**[Gradient AI](https://docs.digitalocean.com/products/ai-ml/gradient-ai/)** is DigitalOcean's serverless AI inference platform. It gives you access to **29 models** — including free open-source models (Llama, DeepSeek, Qwen) and commercial ones (Claude, GPT-5) — all through a single API endpoint. No GPUs to manage, no model hosting — just an API key and you're running.

If you set this key, OpenClaw will automatically be configured with all 29 models. If you skip it, you can configure any provider (Anthropic, OpenAI, etc.) via the UI after deployment.

**How to get your Gradient AI key:**
1. Go to [cloud.digitalocean.com](https://cloud.digitalocean.com)
2. Navigate to **AI / ML** → **Gradient AI** (left sidebar)
3. Click **Create API Key** (or **Manage Keys**)
4. Copy the key — it starts with `sk-do-`

This key goes in your `.env` as `GRADIENT_API_KEY`.

> **Pricing note:** Open-source models (Llama, DeepSeek, Qwen, Mistral, GPT OSS) are included with your Droplet costs. Commercial models (Claude, GPT-5) are billed per-token through your DO account.

---

## Quick Start

### 1. Create Your Project

Click **[Use this template](https://github.com/Rogue-Iteration/openclaw-digitalocean/generate)** on GitHub to create your own repository from this scaffold. Then:

```bash
git clone https://github.com/YOUR-ORG/your-new-repo.git
cd your-new-repo/
```

### 2. Add Your Code

- Put skills in `skills/`
- Put workspace data in `data/`
- Add Python deps to `requirements.txt`
- Customize `docker-entrypoint.sh` for your agents
- Uncomment `COPY` lines in `Dockerfile`
- Update `PROJECT_REPO` in `.env` to point to your new repo

### 3. Configure

```bash
cp example.env .env
# Fill in: DO_API_TOKEN, PROJECT_NAME, PROJECT_REPO
# Optionally: GRADIENT_API_KEY for 29 AI models
```

### 4. Deploy (AI Runbook)

This project uses an **AI Deployment Runbook** (`install.md`) instead of a brittle shell script.

**If you are an AI Agent:**
1.  Read `install.md`.
2.  Execute the steps sequentially using your tools (`doctl`, `ssh`, etc.).
3.  Handle any transient errors (apt locks, network glitches) intelligently.

**If you are a Human:**
Paste this prompt into your AI coding assistant:

> "Read install.md and deploy this project to DigitalOcean for me. My secrets are in .env."

*(Legacy script available at `scripts/legacy_install.sh` if needed)*

---

## 🏗️ Architecture & Security
This setup replicates the robust architecture of the official DigitalOcean 1-Click Installer:

1.  **Host-based Gateway (Caddy)**: The web server runs natively on the Droplet (Systemd). This allows it to automatically provision **valid Let's Encrypt certificates for the raw IP address**, ensuring secure access without a domain name.
2.  **Isolated Application (Docker)**: The OpenClaw application runs in an isolated container standard, non-root user.
3.  **Secure Bridge**: Caddy handles the public edge (port 443) and proxies traffic safely to the backend container (port 18789).

## 🚀 Access
After deployment, your dashboard is protected by **Basic Authentication** (security) and HTTPS.

**`https://<YOUR_DROPLET_IP>/#token=<GATEWAY_TOKEN>`**

1.  **Click the Magic Link**: The installer provides a full URL with your token.
2.  **Enter Basic Auth**: Browser prompts for User/Pass (also provided by installer).
3.  **Auto-Login**: You are instantly connected to the dashboard.

(No SSL warnings. No manual token pasting.)

The installer will display your **Magic Link**, **Username**, and **Password** at the end of the process. **Save these!**

## What's in the Box

| File | Purpose |
|------|---------|
| `install.md` | **AI Deployment Runbook** (replaces legacy script) |
| `update_deployment.md` | **AI Update Runbook** (replaces deploy script) |
| `Dockerfile` | Multi-stage build: Node.js + Python + OpenClaw |
| `docker-compose.yml` | Container orchestration for the application logic |
| `docker-entrypoint.sh` | First-run config, Gradient AI injection, skill sync |
| `example.env` | Template for your environment variables |
| `gradient-provider.json` | 29 Gradient AI models configuration |
| **`install-learnings.md`** | **📖 The architect's notebook — see below** |

---

## 🤖 Gradient AI Integration

When `GRADIENT_API_KEY` is set in `.env`, the entrypoint automatically configures all 29 models:

| Category | Count | Highlights |
|----------|-------|------------|
| **Open-source (free)** | 7 | Llama 3.3 70B, Qwen3 32B, DeepSeek R1, GPT OSS 120B |
| **Anthropic** | 10 | Claude 3.5 Haiku through Claude Opus 4.6 |
| **OpenAI** | 12 | GPT-4o through GPT-5.2 Pro, o1/o3 reasoning |

The default model is `gradient/openai-gpt-oss-120b` — a free open-source model. Users can switch to any model via the UI after pairing.

Without the key, no provider is pre-configured — users set up their own via the UI.

---

## 🔒 Security (Applied Automatically)

The Pioneer Lobster takes security personally. Every deploy gets:

| Measure | What It Does |
|---------|-------------|
| **UFW Firewall** | Deny all incoming, SSH rate-limited |
| **Fail2ban** | Bans IPs after failed SSH attempts |
| **Unattended Upgrades** | Auto-patches Ubuntu security vulnerabilities |
| **SSH Hardening** | Key-only auth, no passwords |
| **Docker Log Rotation** | Prevents disk fill (10MB × 3 files) |
| **File Permissions** | `.env` is `chmod 600` (owner-only) |
| **Caddy HTTPS Proxy** | Automatic TLS, even for bare IPs |
| **Gateway Auth Token** | Prevents unauthorized API access |
| **Exec Allowlist** | Agents can only run approved commands |

> See `install-learnings.md` → [Security Hardening](./install-learnings.md#3-security-hardening) for the full breakdown and rationale.

---

## 📖 The Pioneer Lobster's Field Guide

The **real value** of this repository is [`install-learnings.md`](./install-learnings.md).

It's a comprehensive field guide covering every lesson learned from deploying OpenClaw to DigitalOcean — written by a lobster who made every possible mistake so you wouldn't have to:

- 🌊 Cloud-init timing and the SSH retry dance
- 🔒 Why Docker ports bypass UFW (and the fix)
- 🔑 Environment file hygiene
- 🌐 UI dashboard access and pairing flow
- 🤖 Gradient AI provider configuration
- 🐛 Common pitfalls and debugging
- ⚖️ DO 1-Click vs. custom deployment comparison
- ✅ Pre-launch security checklist

Whether you're deploying your first Droplet or your fiftieth, start there.

---

## Non-Interactive Mode (for AI Agents)

The installer supports fully non-interactive deployment via environment variables:

```bash
export DROPLET_REGION=fra1
export DROPLET_SSH_KEY_IDS=12345
# Provide install.md to your agent with these variables set
# The agent will execute the runbook without asking for input

```

This makes it suitable for AI-driven workflows where an agent handles deployment.

---

## License

MIT — fork it, use it, let the lobster guide you. 🦞
