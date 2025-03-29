#!/bin/bash
set -e

usage() {
    echo "Usage:"
    echo "  $0 build <env>"
    echo "  $0 server <start|stop|restart> <env>"
    echo "  $0 worker <start|stop|restart> <env>"
    echo "  $0 all <start|stop|restart> <env>"
    exit 1
}

# Parse arguments: build expects 2 args, others expect 3.
if [ "$1" = "build" ]; then
    if [ $# -ne 2 ]; then
        usage
    fi
    COMMAND="build"
    ENV_NAME=$2
else
    if [ $# -ne 3 ]; then
        usage
    fi
    TARGET=$1   # "server", "worker", or "all"
    ACTION=$2   # "start", "stop", or "restart"
    ENV_NAME=$3
    if [ "$TARGET" != "server" ] && [ "$TARGET" != "worker" ] && [ "$TARGET" != "all" ]; then
        usage
    fi
    if [[ "$ACTION" != "start" && "$ACTION" != "stop" && "$ACTION" != "restart" ]]; then
        usage
    fi
fi

ENV_FILE=".env-${ENV_NAME}"

if [ ! -f "$ENV_FILE" ]; then
    echo "ERROR: Environment file '$ENV_FILE' not found!"
    exit 1
fi

echo "Loading environment file: $ENV_FILE"
set -a
. "$ENV_FILE"
set +a

# Use WORK_POOL_CONCURRENCY from the env file or default to 2 if not set.
if [ -z "$WORK_POOL_CONCURRENCY" ]; then
    echo "WORK_POOL_CONCURRENCY not defined in $ENV_FILE, using default concurrency limit 2."
    WORK_POOL_CONCURRENCY=2
fi

build_all() {
    echo "Building all images..."
    BUILD_ARGS="--build-arg GLOBAL_INDEX=${GLOBAL_INDEX} \
--build-arg GLOBAL_INDEX_URL=${GLOBAL_INDEX_URL} \
--build-arg GLOBAL_CERT=${GLOBAL_CERT} \
--build-arg HOST_UID=${HOST_UID} \
--build-arg HOST_GID=${HOST_GID} \
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

# Server control functions
start_server() {
    # Check Prefect CLI requirement before starting services
    if [ -n "$WORKER_POOLS" ]; then
        if ! command -v prefect &> /dev/null; then
            echo "ERROR: Prefect CLI is required for work pool creation but not found."
            echo "Please install with: pip install prefect"
            exit 1
        fi
        # Set proper Prefect home directory
        export PREFECT_HOME="${HOME}/.prefect"
        mkdir -p "${PREFECT_HOME}"
    fi

    echo "Starting Prefect Server..."
    docker compose --env-file "$ENV_FILE" -f docker-compose.prefect-server.yml up -d

    if ! docker network ls | grep -q "scan_fleet_scannet"; then
        echo "Creating Docker network: scan_fleet_scannet"
        docker network create scan_fleet_scannet
    fi

    # Create/update work pools after server starts
    if [ -n "$WORKER_POOLS" ]; then
        # Use PREFECT_API_URL from .env file
        if [ -z "$PREFECT_API_URL" ]; then
            echo "ERROR: PREFECT_API_URL not defined in $ENV_FILE"
            exit 1
        fi

        # Display connection info
        echo "Connecting to Prefect API at: ${PREFECT_API_URL}"

        # Wait for server to be ready
        echo "Waiting for Prefect server to become available..."
        MAX_RETRIES=15
        RETRY_INTERVAL=5
        HEALTH_ENDPOINT="${PREFECT_API_URL}/health"
        SUCCESS=0

        for ((i=1; i<=MAX_RETRIES; i++)); do
            if curl --silent --output /dev/null --fail "$HEALTH_ENDPOINT"; then
                if curl --silent --fail "${PREFECT_API_URL%/api*}/version"; then
                    SUCCESS=1
                    break
                else
                    echo "Server partially ready but version endpoint not responding..."
                fi
            fi
            echo "Server not ready (attempt $i/$MAX_RETRIES), retrying in ${RETRY_INTERVAL}s..."
            sleep ${RETRY_INTERVAL}
        done

        if [ $SUCCESS -eq 0 ]; then
            echo "ERROR: Server did not become fully ready after ${MAX_RETRIES} attempts"
            echo "Final check tried endpoints:"
            echo "- Health: ${HEALTH_ENDPOINT}"
            echo "- Version: ${PREFECT_API_URL%/api*}/version"
            exit 1
        fi

        echo "Server connection established successfully!"
        echo "API Version: $(curl --silent ${PREFECT_API_URL%/api*}/version)"

        IFS=',' read -ra POOLS <<< "$WORKER_POOLS"
        for pool_entry in "${POOLS[@]}"; do
            IFS=':' read -r pool_name instance_count <<< "$pool_entry"
            echo "Processing work pool: ${pool_name}"

            # Idempotent pool creation with overwrite
            echo "Attempting to create/update pool '${pool_name}'..."
            if prefect work-pool create --type process "${pool_name}" --overwrite 2>&1; then
                echo "Pool base created/updated successfully"
            else
                echo "Warning: Pool creation returned non-zero exit code (might already exist)"
            fi

            # Update concurrency limit
            echo "Setting concurrency limit to ${WORK_POOL_CONCURRENCY}..."
            if prefect work-pool update "${pool_name}" --concurrency-limit "${WORK_POOL_CONCURRENCY}" 2>&1; then
                echo "Successfully updated ${pool_name} pool settings"
            else
                echo "ERROR: Failed to update work pool ${pool_name}"
                echo "Check pool exists and CLI has proper permissions"
                exit 1
            fi
        done
    else
        echo "No WORKER_POOLS variable defined; skipping work pool setup."
    fi
}

stop_server() {
    echo "Stopping Prefect Server..."
    docker compose --env-file "$ENV_FILE" -f docker-compose.prefect-server.yml down
}

restart_server() {
    stop_server
    start_server
}

# Worker control functions
start_workers() {
    if [ -z "$WORKER_POOLS" ]; then
        echo "WARNING: WORKER_POOLS variable not defined in $ENV_FILE. No workers to start."
        return
    fi

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
            echo "Starting worker instance $i for pool '$pool_name' with worker name '${ENV_NAME}-${i}' (Project: $PROJECT_NAME)..."
            env WORK_POOL="$pool_name" WORKER_NAME="$ENV_NAME" INSTANCE="$i" \
              docker compose --project-name "$PROJECT_NAME" --env-file "$ENV_FILE" -f docker-compose.prefect-worker.yml up -d
        done
    done
}

stop_workers() {
    if [ -z "$WORKER_POOLS" ]; then
        echo "No workers defined to stop."
        return
    fi

    IFS=',' read -ra POOLS <<< "$WORKER_POOLS"
    for pool_entry in "${POOLS[@]}"; do
        IFS=':' read -r pool_name instance_count <<< "$pool_entry"
        if [ -z "$instance_count" ]; then
            instance_count=1
        fi
        for (( i=1; i<=instance_count; i++ )); do
            PROJECT_NAME="prefect-worker-${pool_name}-${i}"
            echo "Stopping worker instance $i for pool '$pool_name' (Project: $PROJECT_NAME)..."
            env WORK_POOL="$pool_name" WORKER_NAME="$ENV_NAME" INSTANCE="$i" \
              docker compose --project-name "$PROJECT_NAME" --env-file "$ENV_FILE" -f docker-compose.prefect-worker.yml down
        done
    done
}

restart_workers() {
    stop_workers
    start_workers
}

# Combined control functions for both server and workers
start_all() {
    start_server
    start_workers
}

stop_all() {
    stop_server
    stop_workers
}

restart_all() {
    stop_all
    start_all
}

# Main command execution
if [ "$COMMAND" = "build" ]; then
    build_all
elif [ "$TARGET" = "server" ]; then
    case "$ACTION" in
        start)   start_server ;;
        stop)    stop_server ;;
        restart) restart_server ;;
        *)       usage ;;
    esac
elif [ "$TARGET" = "worker" ]; then
    case "$ACTION" in
        start)   start_workers ;;
        stop)    stop_workers ;;
        restart) restart_workers ;;
        *)       usage ;;
    esac
elif [ "$TARGET" = "all" ]; then
    case "$ACTION" in
        start)   start_all ;;
        stop)    stop_all ;;
        restart) restart_all ;;
        *)       usage ;;
    esac
else
    usage
fi
