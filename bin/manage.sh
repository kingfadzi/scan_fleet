#!/bin/bash
set -e

usage() {
    echo "Usage:"
    echo "  $0 build <env>"
    echo "  $0 <start|stop|restart> <server|worker|submitter|all> <env>"
    exit 1
}

# Handle 'build' separately
if [ "$1" = "build" ]; then
    if [ $# -ne 2 ]; then
        usage
    fi
    COMMAND="build"
    ENV_NAME=$2
else
    # Handle start/stop/restart logic
    if [ $# -ne 3 ]; then
        usage
    fi
    ACTION=$1             # start | stop | restart
    TARGET=$2             # server | worker | submitter | all
    ENV_NAME=$3           # env name

    if [[ "$ACTION" != "start" && "$ACTION" != "stop" && "$ACTION" != "restart" ]]; then
        usage
    fi

    if [[ "$TARGET" != "server" && "$TARGET" != "worker" && "$TARGET" != "submitter" && "$TARGET" != "all" ]]; then
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

build_all() {
    echo "Building all images..."

    SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
    BUILD_CONTEXT="${SCRIPT_DIR}/.."

    BUILD_ARGS="--build-arg GLOBAL_INDEX=${GLOBAL_INDEX} \
--build-arg GLOBAL_INDEX_URL=${GLOBAL_INDEX_URL} \
--build-arg SOURCE_TARBALL_URLS=${SOURCE_TARBALL_URLS} \
--build-arg GLOBAL_CERT=${GLOBAL_CERT} \
--build-arg HOST_UID=${HOST_UID} \
--build-arg HOST_GID=${HOST_GID} \
--build-arg GRADLE_VERSIONS='${GRADLE_VERSIONS}' \
--build-arg DEFAULT_GRADLE_VERSION=${DEFAULT_GRADLE_VERSION} \
--build-arg TOOLS_TARBALL_URL=${TOOLS_TARBALL_URL} \
--build-arg HTTP_PROXY=${HTTP_PROXY} \
--build-arg HTTPS_PROXY=${HTTPS_PROXY} \
--build-arg NO_PROXY=${NO_PROXY} \
--build-arg FLOW_GIT_STORAGE=${FLOW_GIT_STORAGE} \
--build-arg FLOW_GIT_BRANCH=${FLOW_GIT_BRANCH}"

    docker build --no-cache $BUILD_ARGS -t scanfleet-base -f "$BUILD_CONTEXT/Dockerfile.base" "$BUILD_CONTEXT"
    docker build --no-cache $BUILD_ARGS -t scanfleet-prefect-server -f "$BUILD_CONTEXT/Dockerfile.prefect-server" "$BUILD_CONTEXT"
    docker build --no-cache $BUILD_ARGS -t scanfleet-prefect-worker -f "$BUILD_CONTEXT/Dockerfile.prefect-worker" "$BUILD_CONTEXT"
    docker build --no-cache $BUILD_ARGS -t scanfleet-prefect-submitter -f "$BUILD_CONTEXT/Dockerfile.prefect-submitter" "$BUILD_CONTEXT"

    echo "All images built successfully!"
}

# Server control functions
start_server() {
    echo "Starting Prefect Server..."
    docker compose --env-file "$ENV_FILE" -f docker-compose.prefect-server.yml up -d

    if ! docker network ls | grep -q scan_fleet_scannet; then
        docker network create scan_fleet_scannet >/dev/null
    fi

    if [ -n "$WORKER_POOLS" ]; then
        [ -z "$PREFECT_API_URL" ] && { echo "ERROR: PREFECT_API_URL undefined"; exit 1; }

        echo "Connecting to: ${PREFECT_API_URL}"
        echo -n "Waiting for server "
        for _ in {1..15}; do
            if curl -L --silent --fail --output /dev/null "${PREFECT_API_URL}/health"; then
                echo " Ready!"
                break
            fi
            echo -n "."
            sleep 2
        done

        if ! curl -L --silent --fail "${PREFECT_API_URL}/health"; then
            echo "ERROR: Server failed to start"
            exit 1
        fi

        IFS=',' read -ra POOLS <<< "$WORKER_POOLS"
        for pool_entry in "${POOLS[@]}"; do
            IFS=':' read -r pool_name instance_count pool_concurrency <<< "$pool_entry"

            if [ -z "$pool_name" ] || [ -z "$instance_count" ] || [ -z "$pool_concurrency" ]; then
                echo "ERROR: Invalid WORKER_POOLS entry '${pool_entry}'."
                echo "       Expected format: pool_name:instance_count:concurrency_limit"
                echo "       Example: submitter-pool:5:10"
                exit 1
            fi

            if ! [[ "$instance_count" =~ ^[0-9]+$ ]]; then
                echo "ERROR: Instance count must be numeric. Got '${instance_count}' in entry '${pool_entry}'."
                exit 1
            fi

            if ! [[ "$pool_concurrency" =~ ^[0-9]+$ ]]; then
                echo "ERROR: Concurrency limit must be numeric. Got '${pool_concurrency}' in entry '${pool_entry}'."
                exit 1
            fi

            echo "Recreating work pool '${pool_name}' with concurrency ${pool_concurrency}:"

            delete_response=$(curl -L -sS -o /dev/null -w "%{http_code}" -X DELETE \
                "${PREFECT_API_URL}/work_pools/${pool_name}")

            case $delete_response in
                204|200)
                    echo "Existing work pool ${pool_name} removed."
                    ;;
                404)
                    echo "No existing work pool ${pool_name} to remove."
                    ;;
                *)
                    echo "Warning: Failed to delete work pool ${pool_name} (HTTP status $delete_response)"
                    ;;
            esac

            create_response=$(curl -L -sS -o /dev/null -w "%{http_code}" -X POST \
                "${PREFECT_API_URL}/work_pools" \
                --header "Content-Type: application/json" \
                --data-raw "{
                    \"name\": \"${pool_name}\",
                    \"type\": \"process\",
                    \"base_job_template\": {},
                    \"concurrency_limit\": ${pool_concurrency}
                }")

            case $create_response in
                201)
                    echo "Work pool ${pool_name} recreated successfully."
                    ;;
                *)
                    echo "Warning: Failed to recreate work pool ${pool_name} (HTTP status $create_response)"
                    ;;
            esac
        done
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
        IFS=':' read -r pool_name instance_count pool_concurrency <<< "$pool_entry"

        if [ -z "$pool_name" ] || [ -z "$instance_count" ] || [ -z "$pool_concurrency" ]; then
            echo "ERROR: Invalid WORKER_POOLS entry '${pool_entry}'."
            echo "       Expected format: pool_name:instance_count:concurrency_limit"
            echo "       Example: submitter-pool:5:10"
            exit 1
        fi

        if ! [[ "$instance_count" =~ ^[0-9]+$ ]]; then
            echo "ERROR: Instance count must be numeric. Got '${instance_count}' in entry '${pool_entry}'."
            exit 1
        fi

        for (( i=1; i<=instance_count; i++ )); do
            PROJECT_NAME="prefect-worker-${pool_name}-${i}"
            echo "Building worker instance $i for pool '${pool_name}' (Project: $PROJECT_NAME)..."
            env WORK_POOL="$pool_name" WORKER_NAME="$ENV_NAME" INSTANCE="$i" \
                docker compose --project-name "$PROJECT_NAME" --env-file "$ENV_FILE" -f docker-compose.prefect-worker.yml build --no-cache

            echo "Starting worker instance $i for pool '${pool_name}' (Project: $PROJECT_NAME)..."
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
        IFS=':' read -r pool_name instance_count pool_concurrency <<< "$pool_entry"

        if [ -z "$pool_name" ] || [ -z "$instance_count" ] || [ -z "$pool_concurrency" ]; then
            echo "ERROR: Invalid WORKER_POOLS entry '${pool_entry}'."
            exit 1
        fi

        if ! [[ "$instance_count" =~ ^[0-9]+$ ]]; then
            echo "ERROR: Instance count must be numeric. Got '${instance_count}' in entry '${pool_entry}'."
            exit 1
        fi

        for (( i=1; i<=instance_count; i++ )); do
            PROJECT_NAME="prefect-worker-${pool_name}-${i}"
            echo "Stopping worker instance $i for pool '${pool_name}' (Project: $PROJECT_NAME)..."
            env WORK_POOL="$pool_name" WORKER_NAME="$ENV_NAME" INSTANCE="$i" \
                docker compose --project-name "$PROJECT_NAME" --env-file "$ENV_FILE" -f docker-compose.prefect-worker.yml down
        done
    done
}

restart_workers() {
    stop_workers
    start_workers
}

# Submitter control functions

start_submitter() {
    echo "Preparing checkpoint directory..."
    CHECKPOINT_DIR="${USER_HOME}/submitter-checkpoints"
    mkdir -p "$CHECKPOINT_DIR"
    chown "${HOST_UID}:${HOST_GID}" "$CHECKPOINT_DIR"

    echo "Building Submitter image..."
    docker compose --env-file "$ENV_FILE" -f docker-compose.prefect-submitter.yml build --no-cache submitters

    echo "Starting Submitter container..."
    docker compose --env-file "$ENV_FILE" -f docker-compose.prefect-submitter.yml up -d submitters
}

stop_submitter() {
    echo "Stopping Submitter..."
    docker compose --env-file "$ENV_FILE" -f docker-compose.prefect-submitter.yml down
}

restart_submitter() {
    stop_submitter
    start_submitter
}

# Combined control
start_all() {
    start_server
    start_workers
    start_submitter
}

stop_all() {
    stop_server
    stop_workers
    stop_submitter
}

restart_all() {
    stop_all
    start_all
}

# Dispatch logic
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
elif [ "$TARGET" = "submitter" ]; then
    case "$ACTION" in
        start)   start_submitter ;;
        stop)    stop_submitter ;;
        restart) restart_submitter ;;
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