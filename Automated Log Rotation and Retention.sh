#!/usr/bin/env bash
set -euo pipefail

# -----------------------------------------------------------------------------
# Automated Log Rotation and Retention Script
# -----------------------------------------------------------------------------
LOG_DIR=""
ARCHIVE_DIR=""
FILE_PATTERN="${FILE_PATTERN:-*.log}"
ROTATE_AGE_DAYS="${ROTATE_AGE_DAYS:-1}"       # Rotate logs older than N days
MIN_SIZE_MB="${MIN_SIZE_MB:-0}"               # Optional size threshold in MB (0 = disabled)
RETENTION_DAYS="${RETENTION_DAYS:-30}"        # Delete archived bundles older than N days
ERROR_LOG="${ERROR_LOG:-/var/log/log_rotation_error.log}"
DRY_RUN="false"

usage() {
    cat <<EOF
Usage: $0 -d <log_dir> -a <archive_dir> [options]

Options:
  -d <path>     Source directory containing application logs (required)
  -a <path>     Destination directory for compressed archives (required)
  -p <pattern>  Filename glob pattern to match logs (default: "*.log")
  -r <days>     Rotate logs older than N days (default: 1)
  -s <mb>       Also rotate logs >= N megabytes if inactive (default: 0, disabled)
  -k <days>     Retention period: delete archives older than N days (default: 30)
  -e <path>     Error and audit log file path (default: /var/log/log_rotation_error.log)
  -n            Dry-run mode (preview all actions without modifying or deleting files)
  -h            Show this help message

Environment overrides:
  FILE_PATTERN, ROTATE_AGE_DAYS, MIN_SIZE_MB, RETENTION_DAYS, ERROR_LOG

Examples:
  $0 -d /var/log/myapp -a /var/backups/myapp_logs -r 1 -k 30 -n
  $0 -d /var/log/myapp -a /var/backups/myapp_logs -r 7 -s 50 -k 90
EOF
    exit 1
}

while getopts ":d:a:p:r:s:k:e:nh" opt; do
    case "$opt" in
        d) LOG_DIR="$OPTARG" ;;
        a) ARCHIVE_DIR="$OPTARG" ;;
        p) FILE_PATTERN="$OPTARG" ;;
        r) ROTATE_AGE_DAYS="$OPTARG" ;;
        s) MIN_SIZE_MB="$OPTARG" ;;
        k) RETENTION_DAYS="$OPTARG" ;;
        e) ERROR_LOG="$OPTARG" ;;
        n) DRY_RUN="true" ;;
        h) usage ;;
        :) echo "Error: Option -$OPTARG requires an argument." >&2; usage ;;
        \?) echo "Error: Invalid option -$OPTARG" >&2; usage ;;
    esac
done

if [[ -z "$LOG_DIR" \vert{}\vert{} -z "$ARCHIVE_DIR" ]]; then
    echo "Error: Both -d <log_dir> and -a <archive_dir> are required." >&2
    usage
fi

if [[ ! -d "$LOG_DIR" \vert{}\vert{} ! -r "$LOG_DIR" ]]; then
    echo "Error: Log directory '$LOG_DIR' does not exist or is not readable." >&2
    exit 2
fi

for num in "$ROTATE_AGE_DAYS" "$MIN_SIZE_MB" "$RETENTION_DAYS"; do
    if ! [[ "$num" =~ ^[0-9]+$ ]]; then
        echo "Error: Numeric option expected, got '$num'." >&2
        exit 1
    fi
done

err_dir="$(dirname "$ERROR_LOG")"
mkdir -p "$err_dir" 2>/dev/null || true
touch "$ERROR_LOG" 2>/dev/null || ERROR_LOG="/tmp/log_rotation_error.log"

log_info() {
    printf '[%s] [INFO] %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$1"
}

log_error() {
    local msg="[$(date -u '+%Y-%m-%dT%H:%M:%SZ')] [ERROR] $1"
    printf '%s\n' "$msg" >&2
    printf '%s\n' "$msg" >> "$ERROR_LOG"
}

# -----------------------------------------------------------------------------
# Active Log Protection: Verify no running process holds an open file descriptor
# -----------------------------------------------------------------------------
is_file_in_use() {
    local filepath="$1"

    # 1. Check via lsof if installed
    if command -v lsof >/dev/null 2>&1; then
        if lsof "$filepath" >/dev/null 2>&1; then
            return 0
        fi
    fi

    # 2. Check via fuser if installed
    if command -v fuser >/dev/null 2>&1; then
        if fuser "$filepath" >/dev/null 2>&1; then
            return 0
        fi
    fi

    # 3. Fallback: scan /proc/*/fd symlinks on Linux
    if [[ -d /proc ]]; then
        local canonical_target
        canonical_target="$(readlink -f "$filepath" 2>/dev/null \vert{}\vert{} printf '\%s' "$filepath")"
        if find /proc/[0-9]*/fd -lname "$canonical_target" 2>/dev/null | grep -q .; then
            return 0
        fi
    fi

    # 4. Safety guard: skip files modified within the last 60 seconds
    local now_epoch mod_epoch
    now_epoch="$(date -u '+%s')"
    mod_epoch="$(stat -c '\%Y' "$filepath" 2>/dev/null || stat -f '%m' "$filepath" 2>/dev/null \vert{}\vert{} echo "$now_epoch")"
    if (( now_epoch - mod_epoch < 60 )); then
        return 0
    fi

    return 1
}

if [[ "$DRY_RUN" == "true" ]]; then
    log_info "DRY-RUN MODE ENABLED: No files will be archived, truncated, or deleted."
else
    mkdir -p "$ARCHIVE_DIR" || {
        log_error "Failed to create archive directory '$ARCHIVE_DIR'."
        exit 2
    }
fi

abs_log_dir="$(cd "$LOG_DIR" && pwd -P)"
if [[ -d "$ARCHIVE_DIR" ]]; then
    abs_archive_dir="$(cd "$ARCHIVE_DIR" && pwd -P)"
    if [[ "$abs_archive_dir" == "$abs_log_dir" || "$abs_archive_dir" == "$abs_log_dir"/* ]]; then
        log_error "Archive directory ('$abs_archive_dir') must not reside inside log directory ('$abs_log_dir')."
        exit 2
    fi
fi

# -----------------------------------------------------------------------------
# Step 1: Discover Eligible Log Files (Age or Size) & Filter Out Active Logs
# -----------------------------------------------------------------------------
eligible_files=()
skipped_active=0

while IFS= read -r -d '' candidate; do
    # Never rotate the rotation script's own error log
    if [[ "$candidate" == "$ERROR_LOG" ]]; then
        continue
    fi

    # Evaluate eligibility by age (-mtime +ROTATE_AGE_DAYS) or optional size threshold
    is_old="false"
    is_oversized="false"

    if find "$candidate" -maxdepth 0 -mtime +"$ROTATE_AGE_DAYS" | grep -q .; then
        is_old="true"
    fi

    if (( MIN_SIZE_MB > 0 )); then
        size_bytes="$(stat -c '%s' "$candidate" 2>/dev/null \vert{}\vert{} stat -f '\%z' "$candidate")"
        min_bytes=$(( MIN_SIZE_MB * 1024 * 1024 ))
        if (( size_bytes >= min_bytes )); then
            is_oversized="true"
        fi
    fi

    if [[ "$is_old" != "true" && "$is_oversized" != "true" ]]; then
        continue
    fi

    # Protect active log files currently held open by running applications
    if is_file_in_use "$candidate"; then
        skipped_active=$(( skipped_active + 1 ))
        log_info "PROTECTED (active/open file skipped): $candidate"
        continue
    fi

    eligible_files+=("$candidate")
done < <(find "$abs_log_dir" -maxdepth 1 -type f -name "$FILE_PATTERN" -print0 2>/dev/null)

log_info "Scan complete: ${#eligible_files[@]} eligible log(s) found, ${skipped_active} active log(s) protected."

# -----------------------------------------------------------------------------
# Step 2: Archive, Compress, and Remove Rotated Source Logs
# -----------------------------------------------------------------------------
if (( ${#eligible_files[@]} > 0 )); then
    timestamp="$(date -u '+%Y%m%d_%H%M%S')"
    archive_name="logs_archive_${timestamp}.tar.gz"
    final_archive="${ARCHIVE_DIR\%/}/${archive_name}"
    tmp_archive="${ARCHIVE_DIR%/}/.${archive_name}.tmp.$$"

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would create compressed archive: $final_archive"
        for f in "${eligible_files[@]}"; do
            log_info "[DRY-RUN]   + Include and remove source log: $f"
        done
    else
        trap 'rm -f "$tmp_archive"' EXIT

        # Build list of basenames inside abs_log_dir for clean archive
