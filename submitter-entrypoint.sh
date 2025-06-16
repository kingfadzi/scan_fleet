#!/bin/bash
set -e

echo "[Entrypoint] Starting SSH key setup..."

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

echo "[Entrypoint] Ensuring logs directory exists..."
mkdir -p /app/logs

CLONE_DIR="/app/src"

if [ -d "${CLONE_DIR}/.git" ]; then
    echo "[Entrypoint] Removing existing repo at $CLONE_DIR..."
    rm -rf "${CLONE_DIR}"
fi

echo "[Entrypoint] Cloning $FLOW_GIT_STORAGE on branch $FLOW_GIT_BRANCH..."
GIT_SSH_COMMAND="ssh -i /home/prefect/.ssh/id_ed25519 -o UserKnownHostsFile=/home/prefect/.ssh/known_hosts" \
    git clone --branch "$FLOW_GIT_BRANCH" "$FLOW_GIT_STORAGE" "$CLONE_DIR"

cd "$CLONE_DIR"

echo "[Entrypoint] Capturing environment for cron jobs..."
printenv | sed 's/^/export /' > /app/scripts/env.cron

echo "[Entrypoint] Starting crond (cron daemon) as root..."
crond

echo "[Entrypoint] Switching to user 'prefect' and starting supervisord..."
exec su -s /bin/bash prefect -c 'cd /app/src && exec supervisord -c /etc/supervisord.conf'