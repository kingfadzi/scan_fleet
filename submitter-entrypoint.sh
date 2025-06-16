#!/bin/bash
set -e

echo "[Entrypoint] Starting SSH key setup..."

# === SSH Key Setup for prefect user ===
[ -f /tmp/keys/id_ed25519 ] && {
    mkdir -p /home/prefect/.ssh
    cp /tmp/keys/id_ed25519 /home/prefect/.ssh/
    chmod 600 /home/prefect/.ssh/id_ed25519
    chown prefect:prefect /home/prefect/.ssh/id_ed25519
}

[ -f /tmp/keys/id_ed25519.pub ] && {
    cp /tmp/keys/id_ed25519.pub /home/prefect/.ssh/
    chmod 644 /home/prefect/.ssh/id_ed25519.pub
    chown prefect:prefect /home/prefect/.ssh/id_ed25519.pub
}

[ -f /tmp/keys/known_hosts ] && {
    cp /tmp/keys/known_hosts /home/prefect/.ssh/
    chmod 644 /home/prefect/.ssh/known_hosts
    chown prefect:prefect /home/prefect/.ssh/known_hosts
}

[ -d /home/prefect/.ssh ] && {
    chmod 700 /home/prefect/.ssh
    chown -R prefect:prefect /home/prefect/.ssh
}

# === Ensure logs directory exists ===
mkdir -p /app/logs

# === Clone logic: delete and reclone if /app/src already exists ===
CLONE_DIR="/app/src"

if [ -d "${CLONE_DIR}/.git" ]; then
    echo "[Entrypoint] Removing existing repo at $CLONE_DIR..."
    rm -rf "${CLONE_DIR}"
fi

echo "[Entrypoint] Cloning $FLOW_GIT_STORAGE on branch $FLOW_GIT_BRANCH..."
GIT_SSH_COMMAND="ssh -i /home/prefect/.ssh/id_ed25519 -o UserKnownHostsFile=/home/prefect/.ssh/known_hosts" \
    git clone --branch "$FLOW_GIT_BRANCH" "$FLOW_GIT_STORAGE" "$CLONE_DIR"

# === Change to repo directory ===
cd "$CLONE_DIR"

echo "[Entrypoint] Capturing environment for cron..."
printenv > /app/scripts/env.cron

echo "[Entrypoint] Starting crond (cron daemon)..."
crond

echo "[Entrypoint] Switching to 'prefect' and starting supervisord..."
exec su -s /bin/bash prefect -c 'cd /app/src && exec supervisord -c /etc/supervisord.conf'