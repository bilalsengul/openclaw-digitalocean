# 🦞 OpenClaw Update Runbook

**Goal**: Update the running OpenClaw instance with the latest code from GitHub.
**Executor**: AI Agent
**Tools Required**: `ssh`

---

## Phase 1: Preparation
**Objective**: Connect to the server and navigate to the project.

1.  **Connect**:
    *   *Action*: `ssh root@<DROPLET_IP>`
2.  **Navigate**:
    *   *Action*: `cd /opt/openclaw`

---

## Phase 2: Update Code
**Objective**: Pull the latest changes from the repository.

1.  **Git Pull**:
    *   *Action*: `git pull origin main`
    *   *Note*: If there are local changes preventing pull, ask the user whether to stash (`git stash`) or reset (`git reset --hard`).

2.  **Update Config (Optional)**:
    *   If the user provided a new `.env` file, upload it now:
    *   *Action*: `scp .env root@<DROPLET_IP>:/opt/openclaw/.env`

---

## Phase 3: Rebuild & Restart
**Objective**: Apply changes by rebuilding containers.

1.  **Docker Compose Up**:
    *   *Action*: `docker compose up -d --build --remove-orphans`
    *   *Note*: This rebuilds the `openclaw` image with new code/dependencies and restarts the container. The `caddy` service is managed by the host and does not need restarting unless `Caddyfile` changed (which is rare).

---

## Phase 4: Verification
**Objective**: Ensure the update was successful.

1.  **Check Status**:
    *   *Action*: `docker ps`
    *   *Criteria*: `openclaw` container status is `Up`.

2.  **Check Logs**:
    *   *Action*: `docker logs --tail 50 -f openclaw` (press Ctrl+C to exit)
    *   *Criteria*: No startup crash errors.

3.  **Visual Check**:
    *   *Action*: Visit `https://<DROPLET_IP>/`
    *   *Criteria*: Dashboard loads.

---
**Troubleshooting**:
*   If `apt-get` errors appear during build, retry.
*   If `openclaw` container restarts endlessly, check logs for config errors.
