#!/bin/bash
set -e  # Exit on error

# Validate required environment variable
if [ -z "$PREFECT_DATABASE_CONNECTION_URL" ]; then
    echo "ERROR: PREFECT_DATABASE_CONNECTION_URL is not set. Exiting."
    exit 1
fi

# Extract host and port from PREFECT_DATABASE_CONNECTION_URL
# Assuming URL format: postgresql+asyncpg://username:password@host:port/dbname
DB_HOST=$(echo "$PREFECT_DATABASE_CONNECTION_URL" | awk -F[@:/] '{print $5}')
DB_PORT=$(echo "$PREFECT_DATABASE_CONNECTION_URL" | awk -F[@:/] '{print $6}')

if [ -z "$DB_HOST" ] || [ -z "$DB_PORT" ]; then
    echo "ERROR: Incomplete database connection details in PREFECT_DATABASE_CONNECTION_URL. Exiting."
    exit 1
fi

echo "Checking database connection to $DB_HOST on port $DB_PORT..."

# Wait until PostgreSQL is ready
until pg_isready -h "$DB_HOST" -p "$DB_PORT" -U postgres; do
    echo "Waiting for PostgreSQL to be ready..."
    sleep 5
done

echo "Database is accessible. Checking migrations..."

# Run migrations only if necessary
if ! prefect server database upgrade --check; then
    echo "Applying database migrations..."
    prefect server database upgrade
else
    echo "Database is already up to date."
fi

echo "Starting Prefect Server..."
exec prefect server start --host 0.0.0.0