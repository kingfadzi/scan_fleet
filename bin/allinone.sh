#!/bin/bash
set -e

usage() {
    echo "Usage:"
    echo "  $0 build <env>"
    echo "  $0 start <env>"
    echo "  $0 stop <env>"
    echo "  $0 restart <env>"
    exit 1
}

if [ $# -lt 2 ]; then
    usage
fi

COMMAND=$1
ENV_NAME=$2
ENV_FILE=".env-${ENV_NAME}"

if [ ! -f "$ENV_FILE" ]; then
    echo "ERROR: Environment file '$ENV_FILE' not found!"
    exit 1
fi

echo "Loading environment file: $ENV_FILE"
set -a
. "$ENV_FILE"
set +a

build_all() {
    echo "Building all images..."
    BUILD_ARGS="--build-arg GLOBAL_INDEX=${GLOBAL_INDEX} \
--build-arg GLOBAL_INDEX_URL=${GLOBAL_INDEX_URL} \
--build-arg GLOBAL_CERT=${GLOBAL_CERT} \
--build-arg HOST_UID=${HOST_UID} \
--build-arg HOST_GID=${HOST_GID} \
--build-arg GRADLE_DISTRIBUTIONS_BASE_URL=${GRADLE_DISTRIBUTIONS_BASE_URL} \
--build-arg GRADLE_VERSIONS='${GRADLE_VERSIONS}' \
--build-arg DEFAULT_GRADLE_VERSION=${DEFAULT_GRADLE_VERSION} \
--build-arg TOOLS_TARBALL_URL=${TOOLS_TARBALL_URL}"

    docker build --no-cache $BUILD_ARGS -t scanfleet-base -f Dockerfile.base .
    docker build --no-cache $BUILD_ARGS -t scanfleet-prefect-server -f Dockerfile.prefect-server .
    docker build --no-cache $BUILD_ARGS -t scanfleet-prefect-worker -f Dockerfile.prefect-worker .
    echo "All images built successfully!"
}

start_all() {
    echo "Starting Prefect Server..."
    docker compose --env-file "$ENV_FILE" -f docker-compose.prefect-server.yml up -d

    if ! docker network ls | grep -q "scan_fleet_scannet"; then
        echo "Creating Docker network: scan_fleet_scannet"
        docker network create scan_fleet_scannet
    fi

    if [ -z "$WORKER_POOLS" ]; then
        echo "WARNING: WORKER_POOLS variable not defined in $ENV_FILE. No workers to start."
    else
        echo "Starting Prefect Workers..."
        IFS=',' read -ra POOLS <<< "$WORKER_POOLS"
        for pool_entry in "${POOLS[@]}"; do
            IFS=':' read -r pool_name instance_count <<< "$pool_entry"
            if [ -z "$instance_count" ]; then
                instance_count=1
            fi
            echo "Starting $instance_count worker(s) for pool '$pool_name'..."
            for (( i=1; i<=instance_count; i++ )); do
                PROJECT_NAME="prefect-worker-${pool_name}-${i}"
                echo "Starting worker instance $i for pool '$pool_name' (Project: $PROJECT_NAME)..."
                env WORK_POOL="$pool_name" INSTANCE="$i" \
                  docker compose --project-name "$PROJECT_NAME" --env-file "$ENV_FILE" -f docker-compose.prefect-worker.yml up -d
            done
        done
    fi
    echo "All services started successfully!"
}

stop_all() {
    echo "Stopping Prefect Server..."
    docker compose --env-file "$ENV_FILE" -f docker-compose.prefect-server.yml down

    if [ -z "$WORKER_POOLS" ]; then
        echo "No workers defined to stop."
    else
        IFS=',' read -ra POOLS <<< "$WORKER_POOLS"
        for pool_entry in "${POOLS[@]}"; do
            IFS=':' read -r pool_name instance_count <<< "$pool_entry"
            if [ -z "$instance_count" ]; then
                instance_count=1
            fi
            for (( i=1; i<=instance_count; i++ )); do
                PROJECT_NAME="prefect-worker-${pool_name}-${i}"
                echo "Stopping worker instance $i for pool '$pool_name' (Project: $PROJECT_NAME)..."
                env WORK_POOL="$pool_name" INSTANCE="$i" \
                  docker compose --project-name "$PROJECT_NAME" --env-file "$ENV_FILE" -f docker-compose.prefect-worker.yml down
            done
        done
    fi
    echo "All services stopped."
}

restart_all() {
    stop_all
    start_all
}


case "$COMMAND" in
    build)
        build_all
        ;;
    start)
        start_all
        ;;
    stop)
        stop_all
        ;;
    restart)
        restart_all
        ;;
    *)
        usage
        ;;
esac
