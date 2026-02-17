# 🦞 The Pioneer Lobster's Field Guide to DigitalOcean Deployment

```
         🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊
         🌊                                                🌊
         🌊    "I crawled through every misconfigured       🌊
         🌊     firewall and broken SSH tunnel so you       🌊
         🌊     wouldn't have to."                          🌊
         🌊                                                🌊
         🌊              — The Pioneer Lobster 🦞           🌊
         🌊                                                🌊
         🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊
```

This document captures every hard-won lesson from deploying OpenClaw to DigitalOcean Droplets. It's written for humans, AI agents, and the occasional crustacean who wants to navigate these waters safely.

Whether you're deploying your first Droplet or your fiftieth, these notes will save you time, money, and late-night debugging sessions. The Pioneer Lobster went first. Follow in its claw-steps.

---

## Table of Contents

1. [The Big Picture](#1-the-big-picture)
2. [Droplet Creation & Boot Sequence](#2-droplet-creation--boot-sequence)
3. [Security Hardening](#3-security-hardening)
4. [Docker Patterns](#4-docker-patterns)
5. [OpenClaw Configuration](#5-openclaw-configuration)
6. [Environment File Management](#6-environment-file-management)
7. [Telegram Setup](#7-telegram-setup)
8. [Debugging & Troubleshooting](#8-debugging--troubleshooting)
9. [Common Pitfalls](#9-common-pitfalls)
10. [DO 1-Click vs. Custom Deployment](#10-do-1-click-vs-custom-deployment)
11. [Security Checklist](#11-security-checklist)

---

## 1. The Big Picture

```
   Your Machine                    DigitalOcean
  ┌────────────┐     doctl/SSH    ┌──────────────────────┐
  │   .env     │ ────────────────▶│  Droplet (Ubuntu)    │
  │   code     │                  │  ┌──────────────────┐│
  │   install  │                  │  │ Docker Container  ││
  │   .sh      │                  │  │  ┌─────────────┐ ││
  │            │                  │  │  │  OpenClaw    │ ││
  └────────────┘                  │  │  │  Gateway     │ ││
                                  │  │  │  + Skills    │ ││
                                  │  │  └─────────────┘ ││
       🦞 ◀── Telegram ──────────│  └──────────────────┘│
                                  │  UFW │ fail2ban      │
                                  └──────────────────────┘
```

**The flow:**
1. You fill out `.env` with your API keys and project config
2. `install.sh` uses `doctl` to create a Droplet, harden it, and deploy your code
3. Your OpenClaw project runs inside a Docker container
4. The agent communicates via Telegram (or other channels)
5. All state persists in a Docker volume at `/root/.openclaw`

> [!IMPORTANT]
> **This scaffold is for custom OpenClaw projects** — projects with their own Dockerfiles, skills, and dependencies. For vanilla OpenClaw, use the [DO 1-Click](https://marketplace.digitalocean.com/apps/openclaw) instead. It's literally one button.

---

## 2. Droplet Creation & Boot Sequence

### Image Choice

We use `docker-20-04` — a DO marketplace image with Docker and Docker Compose pre-installed on Ubuntu 20.04. This means:
- ✅ No need to install Docker ourselves (saves 2-3 minutes)
- ✅ Docker is already configured and running
- ⚠️ It's Ubuntu 20.04, not 24.04 (but Docker abstracts most of this away)

> [!TIP]
> If you want Ubuntu 24.04, use `ubuntu-24-04` as the image and install Docker yourself. The DO 1-Click image uses 24.04.

### The Cloud-Init Dance 🩰

When a Droplet is created, it goes through **cloud-init** — an initialization process that finishes setting up the OS. This is where most first-deploy failures hide.

**Problem:** The Droplet may respond to SSH before cloud-init is done. If you start deploying, you'll collide with apt locks and sshd restarts.

**Solution — wait for both SSH and cloud-init:**

```bash
# Wait for SSH (Droplet may not be reachable for 30-60 seconds)
for i in $(seq 1 30); do
  if ssh -o StrictHostKeyChecking=accept-new root@$IP true 2>/dev/null; then
    break
  fi
  sleep 5
done

# Then wait for cloud-init to finish
ssh root@$IP 'cloud-init status --wait > /dev/null 2>&1 || sleep 10'
```

> [!WARNING]
> **sshd restarts during cloud-init.** Your SSH connection may drop mid-command. That's why all remote commands should use a retry wrapper (see the `remote_cmd` function in `install.sh`).

### SSH Retry Pattern

```bash
remote_cmd() {
  local droplet_ip="$1"; shift
  for attempt in 1 2 3; do
    if ssh -o StrictHostKeyChecking=accept-new "root@$droplet_ip" "$@" 2>/dev/null; then
      return 0
    fi
    sleep 5
  done
  # Final attempt — let errors through for debugging
  ssh -o StrictHostKeyChecking=accept-new "root@$droplet_ip" "$@"
}
```

The Pioneer Lobster learned this one the hard way — after a deployment that "succeeded" silently while sshd was restarting mid-firewall-setup. The firewall was never configured. Don't be that lobster.

---

## 3. Security Hardening

This is the section the Pioneer Lobster is most proud of. Every item below is applied automatically by `install.sh`.

### 3.1 UFW Firewall

```bash
ufw default deny incoming    # Block everything
ufw default allow outgoing   # Allow outbound (API calls, git, etc.)
ufw limit ssh/tcp            # Rate-limit SSH (prevents brute force)
ufw --force enable           # Activate
```

**Why `limit` instead of `allow` for SSH?**

`ufw limit ssh/tcp` allows a maximum of 6 connections in 30 seconds from a single IP. After that, the connection is dropped. This stops automated SSH brute-force attacks at the firewall level, *before* they even reach fail2ban or sshd.

> [!CAUTION]
> **Do NOT open ports 2375 or 2376.** These are Docker daemon ports. Exposing them gives anyone on the internet root access to your server via Docker. The DO docker image sometimes has these open by default — our script explicitly deletes them.

**What about port 3120 (OpenClaw gateway)?**

Our Docker Compose binds port 3120 to `127.0.0.1` only. This means:
- ✅ Accessible from inside the Droplet
- ❌ NOT accessible from the internet
- No UFW rule needed — it's simply not listening on the public interface

If you need external HTTPS access (e.g., for a web dashboard), use a reverse proxy like Caddy. See the [DO 1-Click approach](#10-do-1-click-vs-custom-deployment) for how they do it.

### 3.2 Fail2ban

```bash
apt-get install -y fail2ban
systemctl enable fail2ban
systemctl start fail2ban
```

Fail2ban monitors authentication logs and temporarily bans IPs that show malicious patterns (e.g., repeated failed SSH logins). The default config bans IPs for 10 minutes after 5 failed attempts.

**Why both UFW `limit` and fail2ban?**

They operate at different levels:
- `ufw limit` is a blunt rate limiter — blocks fast connection floods
- `fail2ban` watches logs — catches slower, more sophisticated attacks

Together, they cover rapid automated bots (UFW) and patient human attackers (fail2ban).

### 3.3 Unattended Security Upgrades

```bash
apt-get install -y unattended-upgrades
dpkg-reconfigure -f noninteractive unattended-upgrades
```

This enables automatic installation of security patches for Ubuntu packages. Your Droplet will stay patched without manual intervention.

> [!NOTE]
> Unattended-upgrades will **not** update Docker images or your application code. Those require manual updates via `install.sh --update` or `deploy.sh`.

### 3.4 SSH Hardening

```bash
# Disable password authentication (key-only)
sed -i "s/^#*PasswordAuthentication .*/PasswordAuthentication no/" /etc/ssh/sshd_config

# Root can only log in via SSH key, not password
sed -i "s/^#*PermitRootLogin .*/PermitRootLogin prohibit-password/" /etc/ssh/sshd_config

systemctl reload sshd
```

DigitalOcean already enforces SSH keys for droplet creation, but the **sshd config** may still allow password auth. We explicitly disable it.

### 3.5 Docker Log Rotation

```json
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  }
}
```

Written to `/etc/docker/daemon.json`. Without this, Docker logs grow unbounded and will eventually fill your disk. On a small Droplet (25GB disk), a chatty agent can fill the disk in days.

### 3.6 File Permissions

```bash
chmod 600 /opt/openclaw/.env
```

The `.env` file contains API keys and secrets. `chmod 600` means only the file owner (root) can read it. Without this, any user on the system could read your API keys.

### 3.7 Gateway Auth Token

Generated in `docker-entrypoint.sh` on first boot:

```bash
GW_TOKEN=$(head -c 32 /dev/urandom | base64 | tr -d '=/+' | head -c 32)
```

This token is injected into `openclaw.json` and prevents unauthorized access to the OpenClaw gateway API. Without it, anyone who can reach port 3120 can control your agents.

### 3.8 Exec Allowlist

```bash
openclaw approvals allowlist add --target local --agent '*' --pattern "python3 /app/skills/*/scripts/*.py *"
```

OpenClaw agents can execute commands via the `exec` tool. Without an allowlist, an agent could run **any** command on the system. The allowlist restricts execution to specific script patterns.

> [!CAUTION]
> **This is the single most important security setting.** An unrestricted exec tool means your LLM agent can `rm -rf /`, read your API keys, install malware, or anything else root can do. Always use an allowlist in production.

---

## 4. Docker Patterns

### 4.1 Multi-Stage Build

The Dockerfile uses two stages:
1. **base** — Node.js 22 + pnpm + OpenClaw (installed globally)
2. **runtime** — Adds Python 3, pip, build tools, and your Python dependencies

This keeps the image smaller by not carrying Node.js build tools into the final image.

### 4.2 Volume Persistence

```yaml
volumes:
  - openclaw-state:/root/.openclaw
```

The OpenClaw state directory (`~/.openclaw/`) contains:
- `openclaw.json` — configuration (generated on first boot)
- `research.db` — SQLite database (if you use one)
- Agent workspaces — conversation history, paired devices
- Skills — installed from ClawHub or copied from image

**This volume persists across container restarts and rebuilds.** Your configuration and conversation history survive updates.

> [!WARNING]
> `docker compose down -v` **deletes the volume and all state.** Only use this if you want a complete reset. Normally, use `docker compose down` (without `-v`).

### 4.3 Localhost-Only Port Binding

```yaml
ports:
  - "127.0.0.1:3120:3120"
```

This is critical. Without the `127.0.0.1:` prefix, Docker publishes the port on all interfaces — including the public IP. UFW **does not** block Docker-published ports (Docker manipulates iptables directly).

The Pioneer Lobster discovered this when port 3120 was accessible from the entire internet despite UFW showing "deny all incoming." Docker and UFW operate on different iptables chains. Always bind to localhost.

### 4.4 Container Naming

```yaml
container_name: ${PROJECT_NAME:-openclaw}
```

Using the `PROJECT_NAME` env var ensures consistent naming across `docker compose`, log commands, and health checks.

### 4.5 Restart Policy

```yaml
restart: always
```

The container restarts automatically if it crashes, or when the Droplet reboots. For production, this is essential.

---

## 5. OpenClaw Configuration

### 5.1 openclaw.json

Generated once, on first container boot. Lives in the volume at `/root/.openclaw/openclaw.json`. Contains:
- Gateway config (mode, auth)
- Model providers (API keys, endpoints)
- Agent list (names, IDs, workspaces, model bindings)
- Channel config (Telegram, WhatsApp, etc.)
- Tool security settings (exec allowlist mode)

**Never bake this into the Docker image.** It contains secrets and should be generated at runtime from environment variables.

### 5.2 Model Providers

To add a model provider (e.g., OpenRouter, Together AI), inject it via jq in the entrypoint:

```bash
jq --arg key "$API_KEY" --arg url "$BASE_URL" \
  '.models.providers.myprovider = {
    "baseUrl": $url,
    "api": "openai-completions",
    "apiKey": $key,
    "models": [...]
  }' openclaw.json
```

### 5.3 Multi-Agent Setup

Each agent needs an entry in `agents.list`:

```json
{
  "id": "my-agent",
  "name": "Agent Name",
  "default": true,
  "workspace": "/root/.openclaw/agents/my-agent/agent",
  "model": { "primary": "provider/model-id" }
}
```

For multi-agent Telegram routing, use per-agent bot accounts and bindings. See the OpenClaw docs for multi-account Telegram configuration.

### 5.4 Skills

OpenClaw loads skills from `~/.openclaw/skills/`. The entrypoint copies them from `/app/skills/` in the image:

```bash
cp -r /app/skills/* ~/.openclaw/skills/
```

Each skill needs a `SKILL.md` file describing its tools. Scripts live in `scripts/` within the skill directory.

### 5.5 ClawHub

[ClawHub](https://openclaw.ai) is the OpenClaw skill marketplace. You can install published skills:

```bash
npx clawhub@latest install skill-name --dir ~/.openclaw/skills/ --force
```

If ClawHub install fails (e.g., security scan pending), fall back to the local copy.

---

## 6. Environment File Management

### The Golden Rules

1. **Never commit `.env` to git** — add it to `.gitignore`
2. **Never bake `.env` into Docker images** — add it to `.dockerignore`
3. **Transfer via SCP** — `scp .env root@droplet:/opt/openclaw/.env`
4. **Set permissions immediately** — `chmod 600 .env`
5. **Source safely** — use `set -a; source .env; set +a` (exports all vars)

### .dockerignore

```
.env
.env.*
!.env.example
```

The `!.env.example` exception allows the template to be included in the image while excluding real secrets.

### Why SCP and Not Git?

Git stores file history permanently. Even if you `git rm` a `.env` file later, the secrets remain in the commit history. SCP transfers the file directly over SSH without any version control trail.

---

## 7. Telegram Setup

### Creating Bots

1. Open Telegram and find **@BotFather**
2. Send `/newbot`
3. Choose a display name and username (must end in `bot`)
4. Copy the **HTTP API token** → paste into `.env` as `TELEGRAM_BOT_TOKEN`

### Pairing

After deployment:
1. Send any message to your bot on Telegram
2. It replies with a **pairing code**
3. Approve it:

```bash
# On the Droplet:
docker exec <container> openclaw pairing approve telegram <CODE>

# Or from your local machine:
ssh root@<droplet-ip> docker exec <container> openclaw pairing approve telegram <CODE>
```

### allowFrom — Who Can Talk to Your Bot?

Set `TELEGRAM_ALLOWED_IDS` in `.env` to a comma-separated list of numeric Telegram user IDs. This restricts access to only those users.

**Finding your Telegram user ID:**
Deploy without `TELEGRAM_ALLOWED_IDS` first. When you message the bot, it will reply with your numeric user ID. Add it, then re-deploy.

### Group Chats

For multi-agent setups with group chats:
- Enable group mode in BotFather: `/mybots` → select bot → **Bot Settings** → **Allow Groups** → **Enable**
- Add `requireMention: true` in the Telegram config so bots only respond when @mentioned
- Unmentioned messages go to the default agent

---

## 8. Debugging & Troubleshooting

### Container Logs

```bash
# From the Droplet:
docker logs -f <container-name>

# From your local machine:
ssh root@<droplet-ip> docker logs -f <container-name>

# Last 50 lines:
docker logs --tail 50 <container-name>
```

### Cloud-Init Logs

If the Droplet fails during initial boot:
```bash
cat /var/log/cloud-init-output.log
```

### Container Won't Start?

```bash
# Check the build output:
docker compose up --build 2>&1 | tail -50

# Check if port 3120 is already in use:
ss -tlnp | grep 3120

# Check Docker disk usage:
docker system df
```

### SSH Key Issues

```bash
# List your DO SSH keys:
doctl compute ssh-key list

# Import a new key:
doctl compute ssh-key import my-key --public-key-file ~/.ssh/id_rsa.pub
```

### Firewall Debugging

```bash
# Check UFW status:
ufw status verbose

# Check fail2ban status:
fail2ban-client status
fail2ban-client status sshd

# Check if Docker is bypassing UFW (it will!):
iptables -L -n | grep 3120
```

---

## 9. Common Pitfalls

### 🪤 "apt is locked"

**Problem:** During cloud-init, `apt` is locked by the automatic setup process. If you try to install packages immediately after SSH connects, you get:

```
E: Could not get lock /var/lib/apt/lists/lock
```

**Solution:** Wait for cloud-init to finish (see [section 2](#2-droplet-creation--boot-sequence)). Or retry:

```bash
while fuser /var/lib/apt/lists/lock >/dev/null 2>&1; do sleep 2; done
```

### 🪤 Docker Ports Bypass UFW

**Problem:** Docker manipulates iptables directly. Even with `ufw deny`, Docker-published ports are accessible from the internet.

**Solution:** Always bind to `127.0.0.1:PORT:PORT`, never `PORT:PORT`.

### 🪤 Volume Ownership After Rebuild

**Problem:** After rebuilding the Docker image, files copied to the volume may have wrong ownership if you switch between root and non-root users.

**Solution:** Stick with one user. If using non-root, add `chown` commands in the entrypoint.

### 🪤 "Container already exists"

**Problem:** `docker compose up` fails because a container with the same name exists from a previous run.

**Solution:** `docker compose down` first, or use `docker compose up -d --force-recreate`.

### 🪤 Large Docker Images

**Problem:** The multi-stage build installs build-essential, git, and other tools. Images can reach 1-2GB.

**Solution:** Use `.dockerignore` aggressively. Don't copy tests, docs, or `.git/` into the image:

```
.git
tests/
*.md
!data/**/*.md
!skills/**/*.md
```

### 🪤 First-Run vs. Subsequent Starts

**Problem:** `openclaw.json` should only be generated once (first boot). On subsequent container starts, you want to update skills and data without overwriting the config.

**Solution:** Guard generation with a file check:

```bash
if [ ! -f "$STATE_DIR/openclaw.json" ]; then
  # First run — generate config
fi
# Always — sync skills and data
```

### 🪤 Timezone Troubles

**Problem:** Cron-based heartbeats fire at wrong times because the container uses UTC by default.

**Solution:** Set `TZ` in `.env`:

```
TZ=Europe/Berlin
```

And pass it through docker-compose:

```yaml
environment:
  - TZ=${TZ:-UTC}
```

---

## 10. DO 1-Click vs. Custom Deployment

The Pioneer Lobster has explored both routes. Here's when to use each:

| | DO 1-Click | This Scaffold (Custom) |
|---|---|---|
| **Best for** | Vanilla OpenClaw, no custom code | Custom projects with skills, agents, dependencies |
| **Setup time** | 2 minutes (one button) | 10-15 minutes |
| **Architecture** | Native npm + systemd | Docker Compose |
| **TLS/HTTPS** | ✅ Caddy auto-cert (even for IPs!) | ❌ Manual (add Caddy yourself) |
| **Security** | ✅ Full hardening | ✅ Full hardening (we match their features) |
| **Custom Python skills** | ⚠️ Manual setup | ✅ Built-in (Dockerfile) |
| **Custom Dockerfile** | ❌ Not applicable | ✅ Full control |
| **Update mechanism** | `/opt/update-openclaw.sh` | `install.sh --update` or `deploy.sh` |
| **AI agent friendly** | ⚠️ Interactive wizard | ✅ Non-interactive, env-var driven |
| **Auditable** | ⚠️ Packer scripts only | ✅ Full source code |

### What the DO 1-Click Does That We Don't (Yet)

1. **Caddy TLS reverse proxy** — automatic HTTPS, even for raw IP addresses via LetsEncrypt. This is genuinely impressive. If you need external HTTPS, consider adding Caddy as a second service in your docker-compose.

2. **Dedicated non-root user** — DO creates an `openclaw` system user. Our Docker approach runs as root inside the container, which is containerized (less risky), but a non-root user inside Docker would be even better.

3. **Interactive setup wizard** — DO's first-login wizard prompts for API keys. Our approach uses `.env` files instead, which is better for AI agents but less discoverable for beginners.

---

## 11. Security Checklist

Before going live, the Pioneer Lobster recommends verifying:

```
✅ UFW enabled with deny-all + SSH rate-limited
✅ Fail2ban running and monitoring SSH
✅ Unattended-upgrades enabled
✅ SSH password auth disabled (key-only)
✅ Docker log rotation configured
✅ .env file has chmod 600
✅ Docker ports bound to 127.0.0.1 only
✅ Gateway auth token generated
✅ Exec allowlist configured (no unrestricted exec)
✅ TELEGRAM_ALLOWED_IDS set (not open to all)
✅ Docker daemon ports (2375/2376) blocked
✅ .env NOT in git history
✅ .env NOT baked into Docker image
```

Run `install.sh` and all of these are applied automatically. But always verify:

```bash
ssh root@<droplet-ip>
ufw status verbose              # Firewall rules
fail2ban-client status          # Fail2ban running
systemctl status unattended-upgrades  # Auto-updates
grep PasswordAuthentication /etc/ssh/sshd_config  # Should be "no"
cat /etc/docker/daemon.json     # Log rotation
ls -la /opt/openclaw/.env       # Should be -rw-------
docker ps                       # Container running
```

---

```
         🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊
         🌊                                                🌊
         🌊   The Pioneer Lobster has marked the path.     🌊
         🌊   The firewall is up. The keys are safe.       🌊
         🌊   The waters are charted.                      🌊
         🌊                                                🌊
         🌊   Now go build something great. 🦞             🌊
         🌊                                                🌊
         🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊
```
