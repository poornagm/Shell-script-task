#!/usr/bin/env bash
set -euo pipefail

# -----------------------------------------------------------------------------
# Scheduled Daily Log Report Script
# -----------------------------------------------------------------------------
LOG_FILE="${LOG_FILE:-/var/log/app/application.log}"
REPORT_DIR="${REPORT_DIR:-/var/log/app/daily_reports}"
CRON_SCHEDULE="${CRON_SCHEDULE:-5 0 * * *}"   # Default: 00:05 every day
INSTALL_CRON="false"

usage() {
    cat <<EOF
Usage: $0 [options]

Options:
  -f <log_file>     Source application log file (default: /var/log/app/application.log)
  -o <report_dir>   Directory to store generated daily reports (default: /var/log/app/daily_reports)
  -c <cron_expr>    Cron schedule expression when using -i (default: "5 0 * * *")
  -i                Install/update the cron job for automated daily execution
  -h                Show this help message

Environment overrides:
  LOG_FILE, REPORT_DIR, CRON_SCHEDULE

Examples:
  $0 -f /var/log/app/application.log -o /var/log/app/daily_reports
  $0 -f /var/log/app/application.log -o /var/log/app/daily_reports -i
EOF
    exit 1
}

while getopts ":f:o:c:ih" opt; do
    case "$opt" in
        f) LOG_FILE="$OPTARG" ;;
        o) REPORT_DIR="$OPTARG" ;;
        c) CRON_SCHEDULE="$OPTARG" ;;
        i) INSTALL_CRON="true" ;;
        h) usage ;;
        :) echo "Error: Option -$OPTARG requires an argument." >&2; usage ;;
        \?) echo "Error: Invalid option -$OPTARG" >&2; usage ;;
    esac
done

install_cron_job() {
    if ! command -v crontab >/dev/null 2>&1; then
        echo "Error: 'crontab'
