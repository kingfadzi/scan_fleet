#!/bin/bash

set -e  # Exit on error

# Function to show usage
usage() {
    echo "Usage:"
    echo "  $0 start server <env>"
    echo "  $0 start worker <pool-name> <env> <instance>"
    echo "  $0 stop server"
    echo "  $0 stop worker <pool-name> <instance>"
    echo "  $0 restart server <env>"
    echo "  $0 restart worker <pool-name> <env> <instance>"
    exit 1
}

# Ensure at least two arguments are passed
if [ $# -lt 2 ]; then
    usage
fi

# Parse CLI arguments
COMMAND=$1
SERVICE=$2
WORK_POOL=""
INSTANCE=""
ENV_FILE=""

# Load environment file only for start/restart
if [[ "$COMMAND" == "start" || "$COMMAND" == "restart" ]]; then
    if [[ "$SERVICE" == "worker" ]]; then
        if [ $# -lt 4 ]; then
            echo "ERROR: Missing work pool name or instance ID."
            usage
        fi
        WORK_POOL=$3
        ENV_FILE=".env-$4"
        INSTANCE=$5  # Worker instance identifier
    else
        ENV_FILE=".env-$3"
    fi

    # Validate environment file
    if [ -z "$ENV_FILE" ] || [ ! -f "$ENV_FILE" ]; then
        echo "ERROR: Environment file $ENV_FILE not found!"
        exit 1
    fi

    # Load environment variables
    echo "Loading environment variables from $ENV_FILE"
    export $(grep -v '^#' "$ENV_FILE" | xargs)
fi

# Ensure the correct network exists for workers
if [[ "$SERVICE" == "worker" && ("$COMMAND" == "start" || "$COMMAND" == "restart") ]]; then
    if ! docker network ls | grep -q "scan_fleet_scannet"; then
        echo "Creating Docker network: scan_fleet_scannet"
        docker network create scan_fleet_scannet
    fi
fi

# Generate a unique worker container name
if [[ "$SERVICE" == "worker" ]]; then
    CONTAINER_NAME="prefect-worker-${WORK_POOL}-${INSTANCE}"
fi

# Function to start Prefect Server
start_server() {
    echo "Building and starting Prefect Server..."
    docker compose -f docker-compose.prefect-server.yml build --no-cache
    docker compose -f docker-compose.prefect-server.yml up -d
    echo "Prefect Server started successfully!"
}

# Function to start Prefect Worker
start_worker() {
    echo "Building and starting Prefect Worker in pool: $WORK_POOL (Instance: ${INSTANCE})"
    export WORK_POOL="$WORK_POOL"
    docker compose -f docker-compose.prefect-worker.yml build --no-cache
    docker compose -f docker-compose.prefect-worker.yml up -d
    echo "Prefect Worker started successfully in pool: $WORK_POOL (Instance: ${INSTANCE})"
}

# Function to stop services
stop_service() {
    if [[ "$SERVICE" == "worker" ]]; then
        echo "Stopping worker: $CONTAINER_NAME"
        docker rm -f "$CONTAINER_NAME" || echo "Worker $CONTAINER_NAME not running."
    else
        echo "Stopping Prefect Server..."
        docker compose -f docker-compose.prefect-server.yml down
    fi
    echo "$SERVICE stopped."
}

# Function to restart services
restart_service() {
    stop_service
    if [ "$SERVICE" == "server" ]; then
        start_server
    elif [ "$SERVICE" == "worker" ]; then
        start_worker
    else
        usage
    fi
}

# Execute based on the command
case "$COMMAND" in
    start)
        if [ "$SERVICE" == "server" ]; then
            start_server
        elif [ "$SERVICE" == "worker" ]; then
            start_worker
        else
            usage
        fi
        ;;
    stop)
        stop_service
        ;;
    restart)
        restart_service
        ;;
    *)
        usage
        ;;
esac