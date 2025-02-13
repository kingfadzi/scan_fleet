#!/bin/bash

set -e  # Exit on error

echo "Checking database connection..."

# Wait until PostgreSQL is ready
until pg_isready -h $(echo $PREFECT_DATABASE_CONNECTION_URL | awk -F[@:/] '{print $5}') -p $(echo $PREFECT_DATABASE_CONNECTION_URL | awk -F[@:/] '{print $6}') -U postgres; do
  echo "Waiting for PostgreSQL to be ready..."
  sleep 5
done

echo "Database is accessible. Checking migrations..."

# Run migrations only if not already applied
if ! prefect server database upgrade --check; then
  echo "Applying database migrations..."
  prefect server database upgrade
else
  echo "Database is already up to date."
fi

echo "Starting Prefect Server..."
exec prefect server start --host 0.0.0.0