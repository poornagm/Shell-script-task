#!/bin/sh

set -e

# --- Configurable Thresholds (Percentages) ---
CPU_WARN=75
CPU_CRIT=90

MEM_WARN=75
MEM_CRIT=90

DISK_WARN=80
DISK_CRIT=90

# Target mount point for disk check
DISK_MOUNT="/"

# --- Metric Collection ---

# 1. CPU Utilization (calculated from /proc/stat over a 1-second interval)
get_cpu_usage() {
    read -r _ u1 n1 s1 i1 io1 irq1 sirq1 st1 _ < /proc/stat
    sleep 1
    read -r _ u2 n2 s2 i2 io2 irq2 sirq2 st2 _ < /proc/stat

    idle1=$((i1 + io1))
    idle2=$((i2 + io2))

    non_idle1=$((u1 + n1 + s1 + irq1 + sirq1 + st1))
    non_idle2=$((u2 + n2 + s2 + irq2 + sirq2 + st2))

    total1=$((idle1 + non_idle1))
    total2=$((idle2 + non_idle2))

    total_diff=$((total2 - total1))
    idle_diff=$((idle2 - idle1))

    if [ "${total_diff}" -gt 0 ]; then
        echo $(((total_diff - idle_diff) * 100 / total_diff))
    else
        echo 0
    fi
}
# 2. Memory Utilization (parsed from /proc/meminfo)
get_mem_usage() {
    awk '/^MemTotal:/ {total=$2} /^MemAvailable:/ {avail=$2} END {printf "%.0f", (total - avail) * 100 / total}' /proc/meminfo
}

# 3. Disk Utilization (parsed from df for the target mount)
get_disk_usage() {
    df -P "${DISK_MOUNT}" | awk 'NR==2 {gsub("%", "", $5); print $5}'
}

# --- Threshold Evaluation ---

# Evaluates a metric against warning/critical limits (returns 0=HEALTHY, 1=WARNING, 2=CRITICAL)
evaluate_metric() {
    val="$1"
    warn="$2"
    crit="$3"

    if [ "${val}" -ge "${crit}" ]; then
        echo 2
    elif [ "${val}" -ge "${warn}" ]; then
        echo 1
    else
        echo 0
    fi
}

status_label() {
    case "$1" in
        0) echo "HEALTHY" ;;
        1) echo "WARNING" ;;
        2) echo "CRITICAL" ;;
    esac
}

# --- Execution & Reporting ---

cpu_pct=$(get_cpu_usage)
mem_pct=$(get_mem_usage)
disk_pct=$(get_disk_usage)

cpu_code=$(evaluate_metric "${cpu_pct}" "${CPU_WARN}" "${CPU_CRIT}")
mem_code=$(evaluate_metric "${mem_pct}" "${MEM_WARN}" "${MEM_CRIT}")
disk_code=$(evaluate_metric "${disk_pct}" "${DISK_WARN}" "${DISK_CRIT}")

# Determine worst-case overall status
overall_code=0
for code in ${cpu_code} ${mem_code} ${disk_code}; do
    if [ "${code}" -gt "${overall_code}" ]; then
        overall_code="${code}"
    fi
done

echo "=== Server Health Report ==="
printf "CPU Usage:    %3s%% [%s] (Warn: %s%%, Crit: %s%%)\n" "${cpu_pct}" "$(status_label "${cpu_code}")" "${CPU_WARN}" "${CPU_CRIT}"
printf "Memory Usage: %3s%% [%s] (Warn: %s%%, Crit: %s%%)\n" "${mem_pct}" "$(status_label "${mem_code}")" "${MEM_WARN}" "${MEM_CRIT}"
printf "Disk (%s):     %3s%% [%s] (Warn: %s%%, Crit: %s%%)\n" "${DISK_MOUNT}" "${disk_pct}" "$(status_label "${disk_code}")" "${DISK_WARN}" "${DISK_CRIT}"
echo "----------------------------"
echo "OVERALL STATUS: $(status_label "${overall_code}")"

# Exit with corresponding status code (0=HEALTHY, 1=WARNING, 2=CRITICAL)
exit "${overall_code}"
