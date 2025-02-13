#!/bin/bash

# Ensure WORK_POOL is set
if [ -z "$WORK_POOL" ]; then
  echo "ERROR: WORK_POOL is not set!"
  exit 1
fi

echo "Starting Prefect Worker in pool: $WORK_POOL"

# Execute Prefect Worker with the correct work pool
exec prefect worker start -p "$WORK_POOL"
