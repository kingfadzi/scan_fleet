#!/bin/bash
set -e

usage() {
    echo "Usage: $0 <env>"
    echo "  <env>: Environment suffix to load (e.g., production, staging)"
    exit 1
}

if [ $# -lt 1 ]; then
    usage
fi

ENV_NAME=$1
ENV_FILE=".env-${ENV_NAME}"

if [ ! -f "$ENV_FILE" ]; then
    echo "ERROR: Environment file '$ENV_FILE' not found!"
    exit 1
fi

echo "Loading environment file: $ENV_FILE"
set -a
. "$ENV_FILE"
set +a

###########################
# Start Prefect Server
###########################
echo "Starting Prefect Server..."
docker compose --env-file "$ENV_FILE" -f docker-compose.prefect-server.yml up -d

###########################
# Ensure Docker network for workers exists
###########################
if ! docker network ls | grep -q "scan_fleet_scannet"; then
    echo "Creating Docker network: scan_fleet_scannet"
    docker network create scan_fleet_scannet
fi

###########################
# Start Prefect Workers
###########################
if [ -z "$WORKER_POOLS" ]; then
    echo "WARNING: WORKER_POOLS variable not defined in $ENV_FILE. No workers to start."
else
    echo "Starting Prefect Workers..."
    # WORKER_POOLS should be a comma-separated list of pool_name:instance_count.
    IFS=',' read -ra POOLS <<< "$WORKER_POOLS"
    for pool_entry in "${POOLS[@]}"; do
        # Split each entry on ':' to get pool name and instance count.
        IFS=':' read -r pool_name instance_count <<< "$pool_entry"
        if [ -z "$instance_count" ]; then
            instance_count=1
        fi
        echo "Starting $instance_count worker(s) for pool '$pool_name'..."
        for (( i=1; i<=instance_count; i++ )); do
            PROJECT_NAME="prefect-worker-${pool_name}-${i}"
            echo "Starting worker instance $i for pool '$pool_name' (Project: $PROJECT_NAME)..."
            # Pass WORK_POOL and INSTANCE so that docker-compose can use them.
            env WORK_POOL="$pool_name" INSTANCE="$i" \
              docker compose --project-name "$PROJECT_NAME" --env-file "$ENV_FILE" -f docker-compose.prefect-worker.yml up -d
        done
    done
fi

echo "All services started successfully!"