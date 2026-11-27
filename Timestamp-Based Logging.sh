#!/bin/sh

set -e

LOG_DIR="./logs"
LOG_FILE="${LOG_DIR}/app.log"

# Ensure the log directory exists
mkdir -p "${LOG_DIR}"

# Helper function to format and append log entries
log_event() {
    level="$1"
    message="$2"
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    printf "[%s] [%-7s] %s\n" "${timestamp}" "${level}" "${message}" >> "${LOG_FILE}"
}

# Write five sample events to the log file
log_event "INFO"    "Application startup initiated."
log_event "INFO"    "Configuration loaded successfully."
log_event "WARNING" "Cache directory not found; using temporary fallback."
log_event "ERROR"   "Failed to connect to primary database; retrying in 5s."
log_event "INFO"    "Connected to replica database; service is ready."

echo "Wrote 5 events to ${LOG_FILE}:"
cat "${LOG_FILE}"
