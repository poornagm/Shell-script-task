#!/usr/bin/env bash
set -euo pipefail

# -----------------------------------------------------------------------------
# Multi-Server Health Monitoring Automation Script
# -----------------------------------------------------------------------------
HOSTS_FILE=""
SSH_USER="${SSH_USER:-}"
SSH_KEY="${SSH_KEY:-}"
SSH_PORT="${SSH_PORT:-22}"
CONNECT_TIMEOUT="${CONNECT_TIMEOUT:-5}"
CMD_TIMEOUT="${CMD_TIMEOUT:-12}"
MOUNT_POINT="${MOUNT_POINT:-/}"
REPORT_FILE="${REPORT_FILE:-multi_server_health_$(date -u '+%Y%m%d_%H%M%S').txt}"

usage() {
    cat <<EOF
Usage: $0 -f <hosts_file> [options]

Options:
  -f <path>     File with one host per line (supports "host" or "user@host:port") (required)
  -u <user>     Default SSH username when not specified in hosts file
  -i <key_path> Path to SSH private key file
  -p <port>     Default SSH port (default: 22)
  -c <seconds>  SSH connection timeout in seconds (default: 5)
  -t <seconds>  Maximum total SSH command timeout in seconds (default: 12)
  -m <mount>    Filesystem mount point to inspect on each server (default: /)
  -o <path>     Consolidated output report path (default: ./multi_server_health_<timestamp>.txt)
  -h            Show this help message

Environment overrides:
  SSH_USER, SSH_KEY, SSH_PORT, CONNECT_TIMEOUT, CMD_TIMEOUT, MOUNT_POINT, REPORT_FILE

Example:
  $0 -f servers.txt -u opsadmin -i ~/.ssh/id_ed25519 -c 5 -t 15 -o /tmp/fleet_health.txt
EOF
    exit 1
}

while getopts ":f:u:i:p:c:t:m:o:h" opt; do
    case "$opt" in
        f) HOSTS_FILE="$OPTARG" ;;
        u) SSH_USER="$OPTARG" ;;
        i) SSH_KEY="$OPTARG" ;;
        p) SSH_PORT="$OPTARG" ;;
        c) CONNECT_TIMEOUT="$OPTARG" ;;
        t) CMD_TIMEOUT="$OPTARG" ;;
        m) MOUNT_POINT="$OPTARG" ;;
        o) REPORT_FILE="$OPTARG" ;;
        h) usage ;;
        :) echo "Error: Option -$OPTARG requires an argument." >&2; usage ;;
        \?) echo "Error: Invalid option -$OPTARG" >&2; usage ;;
    esac
done

if [[ -z "$HOSTS_FILE" ]]; then
    echo "Error: Hosts file is required (-f <hosts_file>)." >&2
    usage
fi

if [[ ! -f "$HOSTS_FILE" \vert{}\vert{} ! -r "$HOSTS_FILE" ]]; then
    echo "Error: Hosts file '$HOSTS_FILE' does not exist or is not readable." >&2
    exit 2
fi

if [[ -n "$SSH_KEY" && ! -r "$SSH_KEY" ]]; then
    echo "Error: SSH private key '$SSH_KEY' does not exist or is not readable." >&2
    exit 2
fi

for cmd in ssh timeout awk; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "Error: Required command '$cmd' is not installed." >&2
        exit 2
    fi
done

report_dir="$(dirname "$REPORT_FILE")"
mkdir -p
