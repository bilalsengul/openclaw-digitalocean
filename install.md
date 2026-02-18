# 🦞 OpenClaw AI Deployment Runbook

**Goal**: Deploy a hardened, secure OpenClaw instance with valid HTTPS on DigitalOcean.
**Executor**: AI Agent
**Tools Required**: `doctl`, `ssh`, `scp`, `git`

---

## Phase 1: Context & Configuration
**Objective**: Load environment variables and verify prerequisites.

1.  **Read Configuration**:
    *   Read `.env` file to get `DO_API_TOKEN`, `PROJECT_NAME`, `PROJECT_REPO`, `DROPLET_REGION`, `DROPLET_SIZE`, `DROPLET_SSH_KEY_IDS`.
    *   *Validation*: Ensure `DO_API_TOKEN` is not empty.

2.  **Verify `doctl` Auth**:
    *   Run `doctl account get`.
    *   *If failed*: Run `doctl auth init -t <DO_API_TOKEN>`.

---

## Phase 2: Provisioning (The Droplet)
**Objective**: Create a new server instance.

1.  **Check for Existing**:
    *   Run `doctl compute droplet list --format Name,PublicIPv4,Status`.
    *   *If* a droplet named `PROJECT_NAME` exists, ask user if they want to Nuke & Pave (destroy) or Update.

2.  **Create Droplet**:
    *   Command:
        ```bash
        doctl compute droplet create <PROJECT_NAME> \
          --region <DROPLET_REGION> \
          --size <DROPLET_SIZE> \
          --image docker-20-04 \
          --ssh-keys <DROPLET_SSH_KEY_IDS> \
          --wait
        ```
    *   *Output*: Capture the `PublicIPv4` address. Let's call this `DROPLET_IP`.

3.  **Wait for SSH**:
    *   The droplet is "active" before SSH is ready.
    *   *Loop*: Attempt `ssh -o StrictHostKeyChecking=accept-new root@<DROPLET_IP> echo "ready"` every 5 seconds until successful.
    *   *Loop 2 (Cloud-Init)*: Run `ssh root@<DROPLET_IP> "cloud-init status --wait"` to ensure OS setup is complete. **Crucial**: If this is skipped, `apt` locks will cause failures later.

---

## Phase 3: Security Hardening (The Shell)
**Objective**: Lock down the server before deploying the app.

1.  **Configure UFW (Firewall)**:
    *   *Action*: Execute via SSH:
        ```bash
        ufw allow 22/tcp
        ufw limit 22/tcp  # Rate limit SSH
        ufw allow 80/tcp  # Caddy HTTP
        ufw allow 443/tcp # Caddy HTTPS
        ufw default deny incoming
        ufw default allow outgoing
        ufw --force enable
        ```

2.  **Install Fail2ban**:
    *   *Action*: `apt-get install -y fail2ban && systemctl enable fail2ban && systemctl start fail2ban`.

3.  **Configure Unattended Upgrades**:
    *   *Action*: `apt-get install -y unattended-upgrades && dpkg-reconfigure -f noninteractive unattended-upgrades`.

4.  **Docker Security**:
    *   *Action (Log Rotation)*: Write `/etc/docker/daemon.json`:
        ```json
        {
          "log-driver": "json-file",
          "log-opts": { "max-size": "10m", "max-file": "3" }
        }
        ```
    *   *Action (Restart)*: `systemctl restart docker`.
    *   *Action (Close Holes)*: `ufw deny 2375` (just in case).

---

## Phase 4: Host Caddy Setup (The Trick)
**Objective**: Setup Caddy on the host for valid IP-based HTTPS (1-Click Style) with Basic Auth security.

1.  **Install Caddy**:
    *   *Action*:
        ```bash
        apt-get update
        apt-get install -y debian-keyring debian-archive-keyring apt-transport-https curl
        curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
        curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | tee /etc/apt/sources.list.d/caddy-stable.list
        apt-get update
        apt-get install -y caddy
        ```

2.  **Generate Security Credentials**:
    *   *Action (Password)*: `openssl rand -base64 12` -> Capture as `DASHBOARD_PASS`.
    *   *Action (Hash)*: `caddy hash-password --plaintext <DASHBOARD_PASS>` -> Capture as `PASS_HASH`.
    *   *User*: Set username to `admin`.

3.  **Configure Caddyfile**:
    *   *Action*: Write to `/etc/caddy/Caddyfile`:
        ```caddy
        <DROPLET_IP> {
            tls {
                issuer acme {
                    dir https://acme-v02.api.letsencrypt.org/directory
                    profile shortlived
                }
            }
            
            basic_auth {
                admin <PASS_HASH>
            }

            reverse_proxy localhost:18789
        }
        ```

4.  **Restart Caddy**:
    *   *Action*: `systemctl restart caddy`.
    *   *Verification*: `systemctl status caddy`.

---

## Phase 5: Application Deployment
**Objective**: Deploy the Dockerized OpenClaw application.

1.  **Prepare Remote Directory**:
    *   *Action*: `mkdir -p /opt/openclaw`.

2.  **Clone/Pull Code**:
    *   *Action*: `git clone <PROJECT_REPO> /opt/openclaw` (or `git pull` if updating).

3.  **Upload Secrets**:
    *   *Action*: `scp .env root@<DROPLET_IP>:/opt/openclaw/.env`.
    *   *Security*: `ssh root@<DROPLET_IP> "chmod 600 /opt/openclaw/.env"`.

4.  **Start Containers**:
    *   *Action*:
        ```bash
        cd /opt/openclaw
        docker compose up -d --build openclaw
        ```
    *   *Note*: We do NOT start the `caddy` service in docker-compose (if it exists) because we are using Host Caddy. Ensure only `openclaw` starts.

---

## Phase 6: Verification & Handoff
**Objective**: Confirm the deployment is live and secure.

1.  **Wait for Health**:
    *   Wait 20-30 seconds for the container to boot.

2.  **Configure Gateway Token**:
    *   *Action*:
        ```bash
        # Generate a strong token
        export TOKEN=$(openssl rand -hex 16)
        
        # Set it in the container
        ssh root@<DROPLET_IP> "docker exec <PROJECT_NAME> openclaw config set gateway.auth.token $TOKEN"
        
        # Restart to apply
        ssh root@<DROPLET_IP> "docker restart <PROJECT_NAME>"
        ```

3.  **Visual Check**:
    *   *Action*: Navigate the browser to `https://<DROPLET_IP>/`.
    *   *Pass Criteria*: Page loads, Green Lock (Valid Cert), Basic Auth Prompt.

4.  **Final Report**:
    *   **Magic Login Link**: `https://<DROPLET_IP>/#token=$TOKEN`
    *   **Basic Auth**: Username: `admin`, Password: `DASHBOARD_PASS`
    *   **Gateway Token**: `$TOKEN`
    *   *Instructions*: "Click the Magic Link, enter Basic Auth credentials, and you will be automatically logged in."

---
**Troubleshooting Notes**:
*   **Apt Lock**: If `apt-get` fails with lock error, wait 30s and retry.
*   **SSH Refused**: If SSH is refused during boot, wait 10s and retry.
*   **Caddy 502**: If accessing the URL gives 502, the OpenClaw container isn't ready yet. Check `docker logs`.
