#!/bin/sh

set -e

# --- Configuration ---
INPUT_FILE="${1:-servers.txt}"
REACHABLE_FILE="reachable_servers.txt"
UNREACHABLE_FILE="unreachable_servers.txt"

SSH_USER="${SSH_USER:-$USER}"
SSH_PORT="${SSH_PORT:-22}"
CONNECT_TIMEOUT=5

# Verify input file exists
if [ ! -f "${INPUT_FILE}" ]; then
    echo "Error: Input file '${INPUT_FILE}' not found." >&2
    echo "Usage: $0 [server_list_file]" >&2
    exit 1
fi

# Clear or create output files
: > "${REACHABLE_FILE}"
: > "${UNREACHABLE_FILE}"

reachable_count=0
unreachable_count=0

echo "Checking SSH connectivity for servers in '${INPUT_FILE}' (Timeout: ${CONNECT_TIMEOUT}s)..."

# Read input file line by line (handles files lacking a trailing newline)
while IFS= read -r raw_line || [ -n "${raw_line}" ]; do
    # Strip inline comments (#...) and leading/trailing whitespace
    host=$(printf "%s" "${raw_line}" | sed 's/#.*//; s/^[[:space:]]*//; s/[[:space:]]*$//')

    # Skip empty lines
    [ -z "${host}" ] && continue

    printf "  Testing %-25s ... " "${host}"

    # Attempt non-interactive SSH connection
    if ssh -n \
        -p "${SSH_PORT}" \
        -o BatchMode=yes \
        -o ConnectTimeout="${CONNECT_TIMEOUT}" \
        -o StrictHostKeyChecking=accept-new \
        "${SSH_USER}@${host}" "exit 0" >/dev/null 2>&1; then
        echo "REACHABLE"
        echo "${host}" >> "${REACHABLE_FILE}"
        reachable_count=$((reachable_count + 1))
    else
        echo "UNREACHABLE"
        echo "${host}" >> "${UNREACHABLE_FILE}"
        unreachable_count=$((unreachable_count + 1))
    fi
done < "${INPUT_FILE}"

# --- Summary ---
echo "----------------------------------------"
echo "Scan complete:"
echo "  Reachable (${reachable_count}):   ${REACHABLE_FILE}"
echo "  Unreachable (${unreachable_count}): ${UNREACHABLE_FILE}"
