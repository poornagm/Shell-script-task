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
