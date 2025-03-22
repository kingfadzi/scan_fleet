#!/bin/bash

set -e  # Exit on error

# Function to show usage
usage() {
    echo "Usage:"
    echo "  $0 build <env>"
    echo "  $0 start server <env>"
    echo "  $0 start worker <pool-name> <env> <instance>"
    echo "  $0 stop server <env>"
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

# For build command, require an environment parameter and load its .env file
if [[ "$COMMAND" == "build" ]]; then
    if [ $# -lt 2 ]; then
        echo "ERROR: Missing environment argument for build."
        usage
    fi
    ENV_FILE=".env-$2"
    echo "DEBUG: [Build] ENV_FILE='$ENV_FILE'"
    if [ ! -f "$ENV_FILE" ]; then
        echo "ERROR: Environment file $ENV_FILE not found!"
        exit 1
    fi
    # Export variables from the env file so they can be used as build args
    set -a
    . "$ENV_FILE"
    set +a
fi

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

# For stop commands, handle server and worker separately
if [ "$COMMAND" == "stop" ]; then
    if [ "$SERVICE" == "worker" ]; then
        if [ $# -lt 5 ]; then
            echo "ERROR: Missing work pool name, environment, or instance ID for stopping worker."
            usage
        fi
        WORK_POOL=$3
        ENV_FILE=".env-$4"
        INSTANCE=$5
        echo "DEBUG: [Stop Worker] WORK_POOL='$WORK_POOL', INSTANCE='$INSTANCE', ENV_FILE='$ENV_FILE'"
    elif [ "$SERVICE" == "server" ]; then
        if [ $# -lt 3 ]; then
            echo "ERROR: Missing environment argument for stopping server."
            usage
        fi
        ENV_FILE=".env-$3"
        echo "DEBUG: [Stop Server] ENV_FILE='$ENV_FILE'"
        if [ ! -f "$ENV_FILE" ]; then
            echo "ERROR: Environment file $ENV_FILE not found!"
            exit 1
        fi
    fi
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

# Function to build all images with build args from the env file
build_all() {
    echo "Building all images..."

    set -a
    . $ENV_FILE
    set +a

    # Generate build arguments dynamically from .env
    # BUILD_ARGS=$(awk -F= '!/^#/ && NF {print "--build-arg " $1 "=" $2}' .env | tr '\n' ' ')
    # Compose the build arguments using variables loaded from the env file

    BUILD_ARGS="--build-arg GLOBAL_INDEX=${GLOBAL_INDEX} \
--build-arg GLOBAL_INDEX_URL=${GLOBAL_INDEX_URL} \
--build-arg GLOBAL_CERT=${GLOBAL_CERT} \
--build-arg HOST_UID=${HOST_UID} \
--build-arg HOST_GID=${HOST_GID} \
--build-arg GRADLE_DISTRIBUTIONS_BASE_URL=${GRADLE_DISTRIBUTIONS_BASE_URL} \
--build-arg GRADLE_VERSIONS='${GRADLE_VERSIONS}' \
--build-arg DEFAULT_GRADLE_VERSION=${DEFAULT_GRADLE_VERSION} \
--build-arg TOOLS_TARBALL_URL=${TOOLS_TARBALL_URL} \
--build-arg NVM_VERSION=${NVM_VERSION} \
--build-arg NODE_VERSION=${NODE_VERSION} \
--build-arg NVM_NODEJS_ORG_MIRROR=${NVM_NODEJS_ORG_MIRROR} \
--build-arg NVM_PRIVATE_REPO=${NVM_PRIVATE_REPO} \
--build-arg NPM_REGISTRY=${NPM_REGISTRY} \
--build-arg SASS_BINARY=${SASS_BINARY} \
--build-arg HTTP_PROXY=${HTTP_PROXY} \
--build-arg HTTPS_PROXY=${HTTPS_PROXY} \
--build-arg NPM_STRICT_SSL=${NPM_STRICT_SSL} \
--build-arg NO_PROXY=${NO_PROXY}"

    docker build --no-cache $BUILD_ARGS -t scanfleet-base -f Dockerfile.base .
    docker build --no-cache $BUILD_ARGS -t scanfleet-prefect-server -f Dockerfile.prefect-server .
    docker build --no-cache $BUILD_ARGS -t scanfleet-prefect-worker -f Dockerfile.prefect-worker .
    echo "All images built successfully!"
}

# Function to start Prefect Server
start_server() {
    echo "Building Prefect Server image..."
    docker build --no-cache -t scanfleet-prefect-server -f Dockerfile.prefect-server .
    echo "Starting Prefect Server..."
    # Source the environment file so variables (like CONTAINER_HOME) override those in .env
    set -a
    . "$ENV_FILE"
    set +a
    docker compose --env-file "$ENV_FILE" -f docker-compose.prefect-server.yml up -d
    echo "Prefect Server started successfully!"
}

# Function to start Prefect Worker
start_worker() {
    echo "Building Prefect Worker image..."
    docker build --no-cache -t scanfleet-prefect-worker -f Dockerfile.prefect-worker .
    echo "DEBUG: Starting Prefect Worker in pool: '$WORK_POOL' (Instance: '$INSTANCE')"
    # Source the environment file to ensure variables are in the shell for substitution
    set -a
    . "$ENV_FILE"
    set +a
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
        # Source the environment file so variables are set for substitution
        set -a
        . "$ENV_FILE"
        set +a
        env WORK_POOL="$WORK_POOL" INSTANCE="$INSTANCE" \
          docker compose --project-name "$PROJECT_NAME" --env-file "$ENV_FILE" -f docker-compose.prefect-worker.yml down
    else
        echo "Stopping Prefect Server..."
        # Source the environment file to ensure CONTAINER_HOME (and others) are exported in the shell
        set -a
        . "$ENV_FILE"
        set +a
        docker compose --env-file "$ENV_FILE" -f docker-compose.prefect-server.yml down
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
