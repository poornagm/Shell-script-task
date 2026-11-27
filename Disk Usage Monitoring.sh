#!/usr/bin/env bash

set -euo pipefail

THRESHOLD=80
# Exclude pseudo/virtual/read-only special filesystems by default
EXCLUDE_FS="tmpfs|devtmpfs|overlay|squashfs|proc|sysfs|cgroup2?|pstore|debugfs|tracefs|securityfs|fusectl|configfs|efivarfs|autofs|mqueue|hugetlbfs|devpts|binfmt_misc|rpc_pipefs|nfsd"

alerts=0

# -P ensures POSIX output format (no line wrapping on long device names)
# -T includes the filesystem type column
while IFS=$'\t' read -r fs fstype size used avail use_pct mountpoint; do
    # Skip header and entries with non-numeric usage (e.g. "-")
    pct="${use_pct%%%}"
    if ! [[ "$pct" =~ ^[0-9]+$ ]]; then
        continue
    fi

    # Skip excluded virtual/pseudo filesystems
    if [[ "$fstype" =~ ^($EXCLUDE_FS)$ ]]; then
        continue
    fi

    if [ "$pct" -gt "$THRESHOLD" ]; then
        echo "WARNING: Filesystem mounted at '$mountpoint' ($fs, $fstype) is at ${pct}% utilization (exceeds ${THRESHOLD}%)." >&2
        alerts=$((alerts + 1))
    else
        echo "OK:      '$mountpoint' is at ${pct}% utilization."
    fi
done < <(df -PT | awk 'NR > 1 {print $1"\t"$2"\t"$3"\t"$4"\t"$5"\t"$6"\t"$7}')

if [ "$alerts" -gt 0 ]; then
    exit 1
fi
