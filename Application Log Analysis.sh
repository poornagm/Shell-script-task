#!/usr/bin/env bash
set -euo pipefail

LOG_FILE="${1:-}"
TOP_N="${2:-5}"

usage() {
    cat <<EOF
Usage: $0 <log_file_path> [top_n_errors]

Arguments:
  <log_file_path>   Path to the application log file (required)
  [top_n_errors]    Number of top error messages to display (default: 5)

Example:
  $0 /var/log/app/application.log
  $0 /var/log/app/application.log 5
EOF
    exit 1
}

if [[ -z "$LOG_FILE" ]]; then
    echo "Error: Log file path is required." >&2
    usage
fi

if [[ ! -f "$LOG_FILE" ]]; then
    echo "Error: File '$LOG_FILE' does not exist or is not a regular file." >&2
    exit 2
fi

if [[ ! -r "$LOG_FILE" ]]; then
    echo "Error: File '$LOG_FILE' is not readable." >&2
    exit 2
fi

if ! [[ "$TOP_N" =~ ^[1-9][0-9]*$ ]]; then
    echo "Error: [top_n_errors] must be a positive integer." >&2
    exit 1
fi

# Single-pass awk analysis for log-level counts and normalized error message grouping
awk -v top_n="$TOP_N" '
function trim(s) {
    sub(/^[[:space:]]+/, "", s)
    sub(/[[:space:]]+$/, "", s)
    return s
}

function normalize_error(line,    msg) {
    msg = line

    # Remove common leading ISO or syslog timestamps
    sub(/^[0-9]{4}-[0-9]{2}-[0-9]{2}[T ][0-9]{2}:[0-9]{2}:[0-9]{2}(\.[0-9]+)?(Z|[+-][0-9]{2}:?[0-9]{2})?[[:space:]]*/, "", msg)
    sub(/^[A-Z][a-z]{2}[[:space:]]+[0-9]{1,2}[[:space:]]+[0-9]{2}:[0-9]{2}:[0-9]{2}[[:space:]]+([^[:space:]]+[[:space:]]+)?/, "", msg)

    # Remove leading bracketed tags such as [pid:1234] or [thread-1]
    while (msg ~ /^\[[^]]+\][[:space:]]*/) {
        sub(/^\[[^]]+\][[:space:]]*/, "", msg)
    }

    # Strip leading ERROR / ERR / CRITICAL / FATAL level markers and separators
    sub(/^(ERROR|ERR|CRITICAL|CRIT|FATAL)[[:space:]]*[:\-]*[[:space:]]*/, "", msg)

    # Strip trailing [ERROR] or (ERROR) tags if present
    sub(/[[:space:]]*([ERROR]|\(ERROR\))[[:space:]]*$/, "", msg)

    return trim(msg)
}

{
    total_lines++

    # Match standalone log levels (case-insensitive) to avoid false matches inside words
    if ($0 ~ /(^\vert{}[^A-Za-z0-9_])(ERROR\vert{}ERR\vert{}FATAL\vert{}CRITICAL)([^A-Za-z0-9_]\vert{}$)/) {
        errors++
        norm = normalize_error($0)
        if (norm == "") {
            norm = "<empty error message>"
        }
        err_counts[norm]++
    } else if ($0 ~ /(^\vert{}[^A-Za-z0-9_])(WARNING\vert{}WARN)([^A-Za-z0-9_]\vert{}$)/) {
        warnings++
    } else if ($0 ~ /(^\vert{}[^A-Za-z0-9_])INFO([^A-Za-z0-9_]\vert{}$)/) {
        infos++
    }
}

END {
    printf "Log Summary\n"
    printf "===========\n"
    printf "Total lines scanned : %d\n", total_lines + 0
    printf "ERROR count         : %d\n", errors + 0
    printf "WARNING count       : %d\n", warnings + 0
    printf "INFO count          : %d\n\n", infos + 0

    printf "Top %d Most Frequent Error Messages\n", top_n
    printf "====================================\n"
