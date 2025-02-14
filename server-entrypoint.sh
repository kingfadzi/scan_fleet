#!/bin/bash
set -e  # Exit on error

# Validate required environment variable
if [ -z "$PREFECT_DATABASE_CONNECTION_URL" ]; then
    echo "ERROR: PREFECT_DATABASE_CONNECTION_URL is not set. Exiting."
    exit 1
fi

# Parse the PostgreSQL host and port using a Bash regex.
# Assumes the URL is in the format:
#   postgresql+asyncpg://username:password@host:port/database
if [[ "$PREFECT_DATABASE_CONNECTION_URL" =~ ^postgresql\+asyncpg://[^:]+:[^@]+@([^:]+):([0-9]+)/ ]]; then
    DB_HOST="${BASH_REMATCH[1]}"
    DB_PORT="${BASH_REMATCH[2]}"
else
    echo "ERROR: Unable to parse PREFECT_DATABASE_CONNECTION_URL. Exiting."
    exit 1
fi

# Print the extracted host and port for debugging
echo "DEBUG: Extracted DB_HOST=${DB_HOST}, DB_PORT=${DB_PORT}"

echo "Checking database connection to $DB_HOST on port $DB_PORT..."

# Wait until PostgreSQL is ready
until pg_isready -h "$DB_HOST" -p "$DB_PORT" -U postgres; do
    echo "$DB_HOST:$DB_PORT - no response"
    echo "Waiting for PostgreSQL to be ready..."
    sleep 5
done

echo "Database is accessible. Checking migrations..."

# Apply database migrations (without the unsupported --check flag)
prefect server database upgrade

echo "Starting Prefect Server..."
exec prefect server start --host 0.0.0.0