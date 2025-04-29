#!/bin/bash
set -e

# Optional SSH key setup
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
    chown prefect:prefect /home/prefect/.ssh
}

if [ ! -d "/app/.git" ]; then
    echo "[Entrypoint] Cloning $FLOW_GIT_STORAGE on branch $FLOW_GIT_BRANCH..."
    GIT_SSH_COMMAND="ssh -i /home/prefect/.ssh/id_ed25519 -o UserKnownHostsFile=/home/prefect/.ssh/known_hosts" \
        git clone --branch "$FLOW_GIT_BRANCH" "$FLOW_GIT_STORAGE" /app
else
    echo "[Entrypoint] Repo already cloned, skipping."
fi

exec supervisord -c /etc/supervisord.conf
