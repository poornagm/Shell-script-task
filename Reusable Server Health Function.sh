#!/usr/bin/env bash

check_cpu() {
    local cpu_input="${1:-}"
    local threshold="${2:-${CPU_THRESHOLD:-80}}"

    # Strip optional whitespace and trailing '%'
    local cpu_val="${cpu_input//[[:space:]]/}"
    cpu_val="${cpu_val%\%}"
    threshold="${threshold//[[:space:]]/}"
    threshold="${threshold%\%}"

    # Validate numeric values (integer or decimal)
    if ! [[ "$cpu_val" =~ ^[0-9]+([.][0-9]+)?$ ]] || ! [[ "$threshold" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
        printf "Error: Invalid CPU usage ('%s') or threshold ('%s').\n" "$cpu_input" "$threshold" >&2
        return 2
    fi

    # Validate range (0 to 100)
    if ! awk -v c="$cpu_val" -v t="$threshold" 'BEGIN { exit !(c >= 0 && c <= 100 && t >= 0 && t <= 100) }'; then
        printf "Error: Values must be between 0 and 100.\n" >&2
        return 2
    fi

    # Return 0 (success) if at or below threshold, 1 (failure) if above threshold
    if awk -v c="$cpu_val" -v t="$threshold" 'BEGIN { exit !(c <= t) }'; then
        printf "OK: CPU utilization (%s%%) is within threshold (%s%%).\n" "$cpu_val" "$threshold"
        return 0
    else
        printf "ALERT: CPU utilization (%s%%) exceeded threshold (%s%%).\n" "$cpu_val" "$threshold" >&2
        return 1
    fi
}
