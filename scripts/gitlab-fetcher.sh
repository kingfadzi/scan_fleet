#!/bin/bash

source /app/scripts/env.cron
export PYTHONPATH=/app/src
cd /app/src

SCRIPT_NAME="gitlab-fetcher.sh"
LOCKFILE="/tmp/gitlab-fetcher.lock"
DATE=$(date +"%Y-%m-%d")
LOGFILE="/app/logs/gitlab-fetching-${DATE}.log"
ERRFILE="/app/logs/gitlab-fetching-${DATE}.err"
PY_CMD="/usr/bin/python3 flows/flow_runner.py config/flows/discovery/gitlab.yaml"

timestamp() { date +"%Y-%m-%d %H:%M:%S"; }
log() { echo "[$(timestamp)] [$SCRIPT_NAME] $*"; }

if [ -e "$LOCKFILE" ]; then
    log "ERROR: Lockfile exists ($LOCKFILE), previous job may still be running. Skipping." >>"$LOGFILE"
    exit 99
fi

trap 'rm -f "$LOCKFILE"' EXIT
touch "$LOCKFILE"

log "STARTED" >>"$LOGFILE"
$PY_CMD >>"$LOGFILE" 2>>"$ERRFILE"
EXIT_CODE=$?
if [ $EXIT_CODE -eq 0 ]; then
    log "FINISHED successfully." >>"$LOGFILE"
else
    log "FAILED with exit code $EXIT_CODE." >>"$LOGFILE"
fi