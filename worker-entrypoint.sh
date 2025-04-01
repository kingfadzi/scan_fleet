#!/bin/bash
set -e

# Validate required environment variables
missing=false
for var in WORK_POOL WORKER_NAME INSTANCE; do
    if [ -z "${!var}" ]; then
        echo "ERROR: $var is not set!"
        missing=true
    fi
done
if [ "$missing" = true ]; then
    exit 1
fi

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

if [ ! -d "/home/prefect/storage" ]; then
    mkdir -p "/home/prefect/storage"
fi

chmod 755 "/home/prefect/storage"
chown prefect:prefect "/home/prefect/storage"

# Combine CLI-provided WORKER_NAME and INSTANCE for a unique identifier
UNIQUE_NAME="${WORKER_NAME}-${INSTANCE}"
echo "Starting Prefect Worker in pool: ${WORK_POOL} with name: ${UNIQUE_NAME}"

# Then start worker
exec prefect worker start -p "$WORK_POOL" --name "$UNIQUE_NAME" --limit 10
