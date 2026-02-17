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

---

## Quick Start

### 1. Fork & Clone

```bash
# Fork this repo on GitHub, then clone your fork
git clone https://github.com/YOUR-ORG/openclaw-digitalocean.git my-project
cd my-project/
```

### 2. Add Your Code

- Put skills in `skills/`
- Put workspace data in `data/`
- Add Python deps to `requirements.txt`
- Customize `docker-entrypoint.sh` for your agents
- Uncomment `COPY` lines in `Dockerfile`
- Update `PROJECT_REPO` in `.env` to point to your fork

### 3. Configure

```bash
cp example.env .env
# Fill in your API keys and project info
```

### 4. Deploy

```bash
# Validate first (no resources created)
bash install.sh --dry-run

# Create the Droplet and deploy
bash install.sh

# Update an existing deployment
bash install.sh --update
```

That's it. The script creates a hardened Droplet, deploys your Docker containers, and applies all security measures automatically.

---

## What's in the Box

| File | Purpose |
|------|---------|
| `install.sh` | Creates Droplet, hardens it, deploys your code |
| `deploy.sh` | On-server update script (pull + rebuild) |
| `Dockerfile` | Multi-stage build: Node.js + Python + OpenClaw |
| `docker-compose.yml` | Container orchestration with safe defaults |
| `docker-entrypoint.sh` | First-run config + skill syncing |
| `example.env` | Template for your environment variables |
| `requirements.txt` | Python dependencies (initially empty) |
| **`install-learnings.md`** | **📖 The real treasure — see below** |

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
| **Localhost Port Binding** | Gateway not exposed to internet |
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
- 📱 Telegram bot setup and pairing flow
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
bash install.sh
```

This makes it suitable for AI-driven workflows where an agent handles deployment.

---

## License

MIT — fork it, use it, let the lobster guide you. 🦞
