#!/usr/bin/env bash
set -euo pipefail

# -----------------------------------------------------------------------------
# Configurable Defaults
# -----------------------------------------------------------------------------
TARGET_DIR="${1:-}"
DAYS_OLD="${2:-7}"
REPORT_FILE="${3:-old_files_report_$(date -u '+%Y%m%d_%H%M%S').txt}"

usage() {
    cat <<EOF
Usage: $0 <directory_path> [days_old] [report_output_path]

Arguments:
  <directory_path>      Directory to scan recursively (required)
  [days_old]            Age threshold in days (default: 7 -> files older than 7 days)
  [report_output_path]  Output report file path (default: ./old_files_report_<timestamp>.txt)

Example:
  $0 /var/log/myapp
  $0 /var/log/myapp 7 /tmp/old_files_report.txt
EOF
    exit 1
}

if [[ -z "$TARGET_DIR" ]]; then
    echo "Error: Target directory path is required." >&2
    usage
fi

if [[ ! -d "$TARGET_DIR" ]]; then
    echo "Error: '$TARGET_DIR' is not a valid directory." >&2
    exit 2
fi

if ! [[ "$DAYS_OLD" =~ ^[0-9]+$ ]]; then
    echo "Error: [days_old] must be a non-negative integer." >&2
    exit 1
fi

report_dir="$(dirname "$REPORT_FILE")"
mkdir -p "$report_dir"

format_bytes() {
    local bytes="$1"
    awk -v b="$bytes" 'BEGIN {
        split("B KB MB GB TB", units, " ")
        u = 1
        while (b >= 1024 && u < 5) {
            b /= 1024
            u++
        }
        if (u == 1) printf "%d %s", b, units[u]
        else printf "%.2f %s", b, units[u]
    }'
}

scan_timestamp="$(date -u '+%Y-%m-%d %H:%M:%S UTC')"
total_files=0
total_bytes=0

# Build report in a temporary buffer before writing to REPORT_FILE and stdout
tmp_entries="$(mktemp)"
trap 'rm -f "$tmp_entries"' EXIT

# Use -print0 / NUL delimiter so filenames with spaces or special characters work safely
# -mtime +7 matches files last modified strictly more than 7 *
