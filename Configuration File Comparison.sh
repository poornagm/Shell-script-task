#!/usr/bin/env bash
set -euo pipefail

# -----------------------------------------------------------------------------
# Configuration File Comparison Script
# -----------------------------------------------------------------------------
OLD_CONFIG="${1:-}"
NEW_CONFIG="${2:-}"
REPORT_FILE="${3:-config_diff_report_$(date -u '+%Y%m%d_%H%M%S').txt}"

usage() {
    cat <<EOF
Usage: $0 <baseline_config_file> <target_config_file> [report_output_path]

Arguments:
  <baseline_config_file>  Original/old configuration file (required)
  <target_config_file>    New/updated configuration file (required)
  [report_output_path]    Output report path (default: ./config_diff_report_<timestamp>.txt)

Example:
  $0 /etc/myapp/app.conf.bak /etc/myapp/app.conf
  $0 config/prod.env config/staging.env /tmp/env_diff_report.txt
EOF
    exit 1
}

if [[ -z "$OLD_CONFIG" || -z "$NEW_CONFIG" ]]; then
    echo "Error: Both <baseline_config_file> and <target_config_file> are required." >&2
    usage
fi

for cfg in "$OLD_CONFIG" "$NEW_CONFIG"; do
    if [[ ! -f "$cfg" || ! -r "$cfg" ]]; then
        echo "Error: Configuration file '$cfg' does not exist or is not readable." >&2
        exit 2
    fi
done

if ! command -v diff >/dev/null 2>&1; then
    echo "Error: 'diff' utility is required but not installed." >&2
    exit 2
fi

report_dir="$(dirname "$REPORT_FILE")"
mkdir -p "$report_dir"

scan_time="$(date -u '+%Y-%m-%d %H:%M:%S UTC')"

# Generate unified diff with 0 context lines (-U 0) and parse hunks into
# Added, Removed, and Modified categories via awk
diff_exit=0
diff_output="$(diff -u -U 0 "$OLD_CONFIG" "$NEW_CONFIG")" || diff_exit=$?

if (( diff_exit > 1 )); then
    echo "Error: Failed to compare '$OLD_CONFIG' and '$NEW_CONFIG' (diff exit=$diff_exit)." >&2
    exit 2
fi

printf '%s\n' "$diff_output" | awk \
    -v old_file="$OLD_CONFIG" \
    -v new_file="$NEW_CONFIG" \
    -v scan_time="$scan_time" '
function flush_hunk(    min_len, i) {
    if (rem_count == 0 && add_count == 0) {
        return
    }

    min_len = (rem_count < add_count) ? rem_count : add_count

    # Pair consecutive removed + added lines within the same hunk as MODIFIED
    for (i = 1; i <= min_len; i++) {
        mod_total++
        mod_old_ln[mod_total] = rem_ln[i]
        mod_old_txt[mod_total] = rem_txt[i]
        mod_new_ln[mod_total] = add_ln[i]
        mod_new_txt[mod_total] = add_txt[i]
    }

    # Any extra removed lines beyond min_len are pure REMOVED lines
    for (i = min_len + 1; i <= rem_count; i++) {
        rem_total++
        pure_rem_ln[rem_total] = rem_ln[i]
        pure_rem_txt[rem_total] = rem_txt[i]
    }

    # Any extra added lines beyond min_len are pure ADDED lines
    for (i = min_len + 1; i <= add_count; i++) {
        add_total++
        pure_add_ln[add_total] = add_ln[i]
        pure_add_txt[add_total] = add_txt[i]
    }

    rem_count = 0
    add_count = 0
}

BEGIN {
    rem_count = 0
    add_count = 0
    mod_total = 0
    rem_total = 0
    add_total = 0
    cur_old_ln = 0
    cur_new_ln = 0
}

# Skip unified diff file headers
/^--- / || /^\+\+\+ / {
    next
}

# Parse hunk header: @@ -old_start[,old_len] +new_start[,new_len] @@
/^@@ / {
    flush_hunk()

    # Extract starting line numbers
    match($0, /@@ -([0-9]+)(,[0-9]+)? \+([0-9]+)(,[0-9]+)? @@/, parts)
    cur_old_ln = parts[1] + 0
    cur_new_ln = parts[3] + 0
    next
}

/^-/ {
    rem_count++
    rem_ln[rem_count] = cur_old_ln
    rem_txt[rem_count] = substr($0, 2)
    cur_old_ln++
    next
}

/^\+/ {
    add_count++
    add_ln[add_count] = cur_new_ln
    add_txt[add_count] = substr($0, 2)
    cur_new_ln++
    next
}

END {
    flush_hunk()

    printf "================================================================================\n"
    printf "CONFIGURATION FILE COMPARISON REPORT\n"
    printf "================================================================================\n"
    printf "Generated At   : %s\n", scan_time
    printf "Baseline File  : %s\n", old_file
    printf "Target File    : %s\n", new_file
    printf "Summary        : %d added | %d removed | %d modified\n", add_total, rem_total, mod_total
    printf "================================================================================\n\n"

    if (add_total == 0 && rem_total == 0 && mod_total == 0) {
        printf "[OK] No differences found. Both configuration files are identical.\n"
        exit 0
    }

    printf "--- MODIFIED LINES (%d) ---\n", mod_total
    if (mod_total == 0) {
        printf "  (none)\n"
    } else {
        for (i = 1; i <= mod_total; i++) {
            printf "  [Line %d -> %d]\n", mod_old_ln[i], mod_new_ln[i]
            printf "    - OLD: %s\n", mod_old_txt[i]
            printf "    + NEW: %s\n", mod_new_txt[i]
        }
    }

    printf "\n--- ADDED LINES (%d) ---\n", add_total
    if (add_total == 0) {
        printf "  (none)\n"
    } else {
        for (i = 1; i <= add_total; i++) {
            printf "  + [Line %d] %s\n", pure_add_ln[i], pure_add_txt[i]
        }
    }

    printf "\n--- REMOVED LINES (%d) ---\n", rem_total
    if (rem_total == 0) {
        printf "  (none)\n"
    } else {
        for (i = 1; i <= rem_total; i++) {
            printf "  - [Line %d] %s\n", pure_rem_ln[i], pure_rem_txt[i]
        }
    }

    exit 1
}
' | tee "$REPORT_FILE"

exit_status="${PIPESTATUS[1]}"
printf '\nReport saved to: %s\n' "$REPORT_FILE"
exit "$exit_status"
