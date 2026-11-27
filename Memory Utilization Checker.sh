#!/usr/bin/env bash

set -euo pipefail

if [ ! -r /proc/meminfo ]; then
    echo "Error: Cannot read /proc/meminfo." >&2
    exit 1
fi

# Extract values (reported in kB in /proc/meminfo)
mem_total_kb=$(awk '/^MemTotal:/ {print $2}' /proc/meminfo)
mem_avail_kb=$(awk '/^MemAvailable:/ {print $2}' /proc/meminfo)

# Fallback for older kernels without MemAvailable
if [ -z "$mem_avail_kb" ]; then
    mem_free_kb=$(awk '/^MemFree:/ {print $2}' /proc/meminfo)
    buffers_kb=$(awk '/^Buffers:/ {print $2}' /proc/meminfo)
    cached_kb=$(awk '/^Cached:/ {print $2}' /proc/meminfo)
    mem_avail_kb=$((mem_free_kb + buffers_kb + cached_kb))
fi

if [ -z "$mem_total_kb" ] || [ "$mem_total_kb" -le 0 ]; then
    echo "Error: Unable to determine total memory." >&2
    exit 1
fi

mem_used_kb=$((mem_total_kb - mem_avail_kb))

# Format values into human-readable units (MB/GB) and calculate percentage via awk
read -r total_fmt used_fmt avail_fmt util_pct exceeded < <(
    awk -v t="$mem_total_kb" -v u="$mem_used_kb" -v a="$mem_avail_kb" '
    function fmt(kb) {
        if (kb >= 1048576) return sprintf("%.2f GiB", kb / 1048576);
        if (kb >= 1024)    return sprintf("%.2f MiB", kb / 1024);
        return sprintf("%d KiB", kb);
    }
    BEGIN {
        pct = (u / t) * 100;
        ex  = (pct > 80) ? 1 : 0;
        printf "%s|%s|%s|%.2f|%d\n", fmt(t), fmt(u), fmt(a), pct, ex;
    }' | IFS='|' read -r tf uf af up ex; printf "%s\t%s\t%s\t%s\t%s\n" "$tf" "$uf" "$af" "$up" "$ex"
)

echo "Total Memory:     $total_fmt"
echo "Used Memory:      $used_fmt"
echo "Available Memory: $avail_fmt"
echo "Utilization:      ${util_pct}%"

if [ "$exceeded" -eq 1 ]; then
    echo "Status:           WARNING - Memory utilization exceeds 80%."
else
    echo "Status:           OK - Memory utilization is within 80%."
fi
