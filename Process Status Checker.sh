#!/usr/bin/env bash

set -euo pipefail

printf "Enter the process name: "
read -r proc_name

if [ -z "$proc_name" ]; then
    echo "Error: No process name entered." >&2
    exit 1
fi

# Collect matching PIDs, excluding this script's own PID
mapfile -t pids < <(pgrep -x -- "$proc_name" 2>/dev/null | awk -v self="$$" '$1 != self')

if [ "${#pids[@]}" -gt 0 ]; then
    echo "Process '$proc_name' is running."
    echo "PID(s): ${pids[*]}"
else
    echo "PROCESS NOT RUNNING"
fi
