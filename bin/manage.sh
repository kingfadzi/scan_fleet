#!/bin/bash

set -e  # Exit on error

# Function to show usage
usage() {
    echo "Usage:"
    echo "  $0 build"
    echo "  $0 start server <env>"
    echo "  $0 start worker <pool-name> <env> <instance>"
    echo "  $0 stop server"
    echo "  $0 stop worker <pool-name> <env> <instance>"
    echo "  $0 restart server <env>"
    echo "  $0 restart worker <pool-name> <env> <instance>"
    exit 1
}

# Ensure at least one argument is passed
if [ $# -lt 1 ]; then
    usage
fi

COMMAND=$1
SERVICE=$2
WORK_POOL=""
INSTANCE=""
ENV_FILE=""

echo "DEBUG: COMMAND='$COMMAND', SERVICE='$SERVICE', All Args: $@"

# For start/restart commands, load the env file and variables
if [[ "$COMMAND" == "start" || "$COMMAND" == "restart" ]]; then
    if [[ "$SERVICE" == "worker" ]]; then
        if [ $# -lt 5 ]; then
            echo "ERROR: Missing work pool name, environment, or instance ID."
            usage
        fi
        WORK_POOL=$3
        ENV_FILE=".env-$4"
        INSTANCE=$5
        echo "DEBUG: [Start/Restart Worker] WORK_POOL='$WORK_POOL', INSTANCE='$INSTANCE', ENV_FILE='$ENV_FILE'"
    else
        if [ $# -lt 3 ]; then
            echo "ERROR: Missing environment argument."
            usage
        fi
        ENV_FILE=".env-$3"
        echo "DEBUG: [Start/Restart Server] ENV_FILE='$ENV_FILE'"
    fi

    if [ -z "$ENV_FILE" ] || [ ! -f "$ENV_FILE" ]; then
        echo "ERROR: Environment file $ENV_FILE not found!"
        exit 1
    fi
fi

# For stop worker command, assign pool, env, and instance from arguments
if [ "$COMMAND" == "stop" ] && [ "$SERVICE" == "worker" ]; then
    if [ $# -lt 5 ]; then
        echo "ERROR: Missing work pool name, environment, or instance ID for stopping worker."
        usage
    fi
    WORK_POOL=$3
    ENV_FILE=".env-$4"
    INSTANCE=$5
    echo "DEBUG: [Stop Worker] WORK_POOL='$WORK_POOL', INSTANCE='$INSTANCE', ENV_FILE='$ENV_FILE'"
fi

# For worker start/restart commands, ensure the Docker network exists
if [[ "$SERVICE" == "worker" && ( "$COMMAND" == "start" || "$COMMAND" == "restart" ) ]]; then
    if ! docker network ls | grep -q "scan_fleet_scannet"; then
        echo "DEBUG: Creating Docker network: scan_fleet_scannet"
        docker network create scan_fleet_scannet
    fi
fi

# For worker commands, define a unique project name based on WORK_POOL and INSTANCE.
if [[ "$SERVICE" == "worker" ]]; then
    PROJECT_NAME="prefect-worker-${WORK_POOL}-${INSTANCE}"
    echo "DEBUG: Generated PROJECT_NAME: '$PROJECT_NAME'"
fi

# Function to build all images
build_all() {
    echo "Building all images..."
    docker build --no-cache -t scanfleet-base -f Dockerfile.base .
    docker build --no-cache -t scanfleet-prefect-server -f Dockerfile.prefect-server .
    docker build --no-cache -t scanfleet-prefect-worker -f Dockerfile.prefect-worker .
    echo "All images built successfully!"
}

# Function to start Prefect Server
start_server() {
    echo "Building Prefect Server image..."
    docker build --no-cache -t scanfleet-prefect-server -f Dockerfile.prefect-server .
    echo "Starting Prefect Server..."
    docker compose --env-file "$ENV_FILE" -f docker-compose.prefect-server.yml up -d
    echo "Prefect Server started successfully!"
}

# Function to start Prefect Worker
start_worker() {
    echo "Building Prefect Worker image..."
    docker build --no-cache -t scanfleet-prefect-worker -f Dockerfile.prefect-worker .
    echo "DEBUG: Starting Prefect Worker in pool: '$WORK_POOL' (Instance: '$INSTANCE')"
    # Explicitly pass WORK_POOL and INSTANCE to Docker Compose
    env WORK_POOL="$WORK_POOL" INSTANCE="$INSTANCE" \
      docker compose --project-name "$PROJECT_NAME" --env-file "$ENV_FILE" -f docker-compose.prefect-worker.yml up -d
    echo "Prefect Worker started successfully in pool: '$WORK_POOL' (Instance: '$INSTANCE')"
}

# Function to stop services
stop_service() {
    if [[ "$SERVICE" == "worker" ]]; then
        echo "DEBUG: Stopping worker container for pool '$WORK_POOL', instance '$INSTANCE'"
        echo "DEBUG: Using project name: '$PROJECT_NAME'"
        # Explicitly pass WORK_POOL and INSTANCE so Docker Compose can substitute them
        env WORK_POOL="$WORK_POOL" INSTANCE="$INSTANCE" \
          docker compose --project-name "$PROJECT_NAME" --env-file "$ENV_FILE" -f docker-compose.prefect-worker.yml down
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
    build)
        build_all
        ;;
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
