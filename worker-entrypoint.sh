#!/bin/bash

# Ensure required environment variables are set
missing=false

# Load the environment file
if [ -z "$ENV_FILE" ]; then
  echo "ERROR: ENV_FILE is not set!"
  missing=true
fi

if [ -f "$ENV_FILE" ]; then
  echo "Loading environment file: $ENV_FILE"
  set -a
  source "$ENV_FILE"
  set +a
else
  echo "ERROR: Environment file '$ENV_FILE' not found!"
  missing=true
fi

# Check for required variables
if [ -z "$WORK_POOL" ]; then
  echo "ERROR: WORK_POOL is not set!"
  missing=true
fi

if [ -z "$WORKER_NAME" ]; then
  echo "ERROR: WORKER_NAME is not set!"
  missing=true
fi

if [ -z "$INSTANCE" ]; then
  echo "ERROR: INSTANCE is not set!"
  missing=true
fi

if [ "$missing" = true ]; then
  exit 1
fi

# SSH Setup
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

[ -f /tmp/keys/java.cacerts ] && {
    cp /tmp/keys/java.cacerts /home/prefect/
    chmod 755 /home/prefect/java.cacerts
    chown prefect:prefect /home/prefect/java.cacerts
}

[ -d /home/prefect/.ssh ] && {
    chmod 700 /home/prefect/.ssh
    chown prefect:prefect /home/prefect/.ssh
}

# Create unique worker name
UNIQUE_NAME="${WORKER_NAME}-${INSTANCE}"

echo "Starting Prefect Worker in pool: $WORK_POOL with name: $UNIQUE_NAME"

exec prefect worker start -p "$WORK_POOL" --name "$UNIQUE_NAME"