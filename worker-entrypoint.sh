#!/bin/bash

# Ensure WORK_POOL is set
if [ -z "$WORK_POOL" ]; then
  echo "ERROR: WORK_POOL is not set!"
  exit 1
fi

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

[ -f /tmp/keys/tls-ca-bundle.pem ] && {
    cp /tmp/keys/tls-ca-bundle.pem /etc/ssl/certs/
    chmod 644 /etc/ssl/certs/tls-ca-bundle.pem
    chown prefect:prefect /etc/ssl/certs/tls-ca-bundle.pem
}

[ -d /home/prefect/.ssh ] && {
    chmod 700 /home/prefect/.ssh
    chown prefect:prefect /home/prefect/.ssh
}

rm -rf /home/prefect/.kantra/custom-rulesets
if ! git clone "$RULESETS_GIT_URL" /home/prefect/.kantra/custom-rulesets; then
    echo "ERROR: Failed cloning rulesets from $RULESETS_GIT_URL"
    exit 1
fi

echo "Starting Prefect Worker in pool: $WORK_POOL"

exec prefect worker start -p "$WORK_POOL"
