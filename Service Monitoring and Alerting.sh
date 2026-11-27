#!/usr/bin/env bash
set -euo pipefail

# -----------------------------------------------------------------------------
# Configurable Defaults (can be overridden via CLI flags or environment vars)
# -----------------------------------------------------------------------------
SERVICE_NAME="${SERVICE_NAME:-}"
LOG_FILE="${LOG_FILE:-/var/log/service_monitor.log}"
NOTIFY_METHOD="${NOTIFY_METHOD:-stdout}"   # stdout | email | webhook
ADMIN_EMAIL="${ADMIN_EMAIL:-admin@example.com}"
WEBHOOK_URL="${WEBHOOK_URL:-}"
HOST_NAME="$(hostname -f 2>/dev/null || hostname)"

usage() {
    cat <<EOF
Usage: $0 -s <service_name> [options]

Options:
  -s <name>     Target application service name (required)
  -l <path>     Log file path (default: /var/log/service_monitor.log)
  -m <method>   Notification method: stdout | email | webhook (default: stdout)
  -e <email>    Administrator email address (used when -m email)
  -w <url>      Webhook endpoint URL (used when -m webhook)
  -h            Show this help message

Environment overrides:
  SERVICE_NAME, LOG_FILE, NOTIFY_METHOD, ADMIN_EMAIL, WEBHOOK_URL
EOF
    exit 1
}

while getopts ":s:l:m:e:w:h" opt; do
    case "$opt" in
        s) SERVICE_NAME="$OPTARG" ;;
        l) LOG_FILE="$OPTARG" ;;
