#!/usr/bin/env bash
set -euo pipefail

# -----------------------------------------------------------------------------
# Website Availability & Latency Monitoring Script
# -----------------------------------------------------------------------------
URLS_FILE=""
SLOW_THRESHOLD_SEC="${SLOW_THRESHOLD_SEC:-2.0}"
TIMEOUT_SEC="${TIMEOUT_SEC:-10}"
REPORT_FILE="${REPORT_FILE:-website_health_report_$(date -u '+%Y%m%d_%H%M%S').txt}"

usage() {
    cat <<EOF
Usage: $0 -f <urls_file> [options]

Options:
  -f <path>     Path to file containing one URL per line (required)
  -s <seconds>  Slow response threshold in seconds (default: 2.0)
  -t <seconds>  curl request timeout in seconds (default: 10)
  -o <path>     Output report file path (default: ./website_health_report_<timestamp>.txt)
  -h            Show this help message

Environment overrides:
  SLOW_THRESHOLD_SEC, TIMEOUT_SEC, REPORT_FILE

Example:
  $0 -f urls.txt -s 1.5 -t 8 -o /tmp/site_status.txt
EOF
    exit 1
}

while getopts ":f:s:t:o:h" opt; do
    case "$opt" in
        f) URLS_FILE="$OPTARG" ;;
        s) SLOW_THRESHOLD_SEC="$OPTARG" ;;
        t) TIMEOUT_SEC="$OPTARG" ;;
        o) REPORT_FILE="$OPTARG" ;;
        h) usage ;;
        :) echo "Error: Option -$OPTARG requires an argument." >&2; usage ;;
        \?) echo "Error: Invalid option -$OPTARG" >&2; usage ;;
    esac
done

if [[ -z "$URLS_FILE" ]]; then
    echo "Error: URLs file path is required (-f <urls_file>)." >&2
    usage
fi

if [[ ! -f "$URLS_FILE" \vert{}\vert{} ! -r "$URLS_FILE" ]]; then
    echo "Error: File '$URLS_FILE' does not exist or is not readable." >&2
    exit 2
fi

for val in "$SLOW_THRESHOLD_SEC" "$TIMEOUT_SEC"; do
    if ! [[ "$val" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
        echo "Error: Numeric value expected, got '$val'." >&2
        exit 1
    fi
done

if ! command -v curl >/dev/null 2>&1; then
    echo "Error: 'curl' is required but not installed." >&2
    exit 2
fi

report_dir="$(dirname "$REPORT_FILE")"
mkdir -p "$report_dir"

is_float_gt() {
    awk -v a="$1" -v b="$2" 'BEGIN { exit !(a > b) }'
}

scan_time="$(date -u '+%Y-%m-%d %H:%M:%S UTC')"
total_urls=0
healthy_urls=0
slow_urls=0
down_urls=0

tmp_all
