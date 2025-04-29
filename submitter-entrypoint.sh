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

# === Clone the Git repo into /app/src only if not already present ===
CLONE_DIR="/app/src"

if [ ! -d "${CLONE_DIR}/.git" ]; then
    echo "[Entrypoint] Cloning $FLOW_GIT_STORAGE on branch $FLOW_GIT_BRANCH into $CLONE_DIR..."
    GIT_SSH_COMMAND="ssh -i /home/prefect/.ssh/id_ed25519 -o UserKnownHostsFile=/home/prefect/.ssh/known_hosts" \
        git clone --branch "$FLOW_GIT_BRANCH" "$FLOW_GIT_STORAGE" "$CLONE_DIR"
else
    echo "[Entrypoint] Repo already exists at $CLONE_DIR, skipping clone."
fi

# === Change to /app/src before supervisor ===
cd /app/src

# === Launch supervisor ===
echo "[Entrypoint] Starting supervisord..."
exec supervisord -c /etc/supervisord.conf
