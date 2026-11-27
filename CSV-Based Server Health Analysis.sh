#!/usr/bin/env bash
set -euo pipefail

# -----------------------------------------------------------------------------
# CSV-Based Server Health Analysis Script
# -----------------------------------------------------------------------------
CSV_FILE=""
CPU_THRESHOLD="${CPU_THRESHOLD:-80}"
MEM_THRESHOLD="${MEM_THRESHOLD:-85}"
DISK_THRESHOLD="${DISK_THRESHOLD:-90}"
REPORT_FILE="${REPORT_FILE:-unhealthy_servers_report_$(date -u '+%Y%m%d_%H%M%S').txt}"

usage() {
    cat <<EOF
Usage: $0 -f <csv_file> [options]

Options:
  -f <path>     Input CSV file with columns: hostname,cpu,memory,disk (required)
  -c <percent>  CPU utilization threshold in % (default: 80)
  -m <percent>  Memory utilization threshold in % (default: 85)
  -d <percent>  Disk utilization threshold in % (default: 90)
  -o <path>     Output report file path (default: ./unhealthy_servers_report_<timestamp>.txt)
  -h            Show this help message

Environment overrides:
  CPU_THRESHOLD, MEM_THRESHOLD, DISK_THRESHOLD, REPORT_FILE

Example:
  $0 -f servers.csv -c 75 -m 80 -d 85 -o /tmp/unhealthy_servers.txt
EOF
    exit 1
}

while getopts ":f:c:m:d:o:h" opt; do
    case "$opt" in
        f) CSV_FILE="$OPTARG" ;;
        c) CPU_THRESHOLD="$OPTARG" ;;
        m) MEM_THRESHOLD="$OPTARG" ;;
        d) DISK_THRESHOLD="$OPTARG" ;;
        o) REPORT_FILE="$OPTARG" ;;
        h) usage ;;
        :) echo "Error: Option -$OPTARG requires an argument." >&2; usage ;;
        \?) echo "Error: Invalid option -$OPTARG" >&2; usage ;;
    esac
done

if [[ -z "$CSV_FILE" ]]; then
    echo "Error: CSV file path is required (-f <csv_file>)." >&2
    usage
fi

if [[ ! -f "$CSV_FILE" \vert{}\vert{} ! -r "$CSV_FILE" ]];
