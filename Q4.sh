#!/usr/bin/env bash

printf "Enter CPU utilization (0-100): "
read -r cpu_input

# Strip optional whitespace and trailing '%'
cpu_val="${cpu_input//[[:space:]]/}"
cpu_val="${cpu_val%\%}"

# Validate numeric input (integer or decimal)
if ! [[ "$cpu_val" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
    echo "Error: '$cpu_input' is not a valid CPU utilization number." >&2
    exit 1
fi

# Validate range (0 to 100) using awk for floating-point support
if ! awk -v v="$cpu_val" 'BEGIN { exit !(v >= 0 && v <= 100) }'; then
    echo "Error: CPU utilization must be between 0 and 100." >&2
    exit 1
fi

# Classify utilization:
#   < 70       -> NORMAL
#   70 to 85   -> WARNING
#   > 85       -> CRITICAL
status=$(awk -v v="$cpu_val" 'BEGIN {
    if (v < 70)      print "NORMAL";
    else if (v <= 85) print "WARNING";
    else              print "CRITICAL";
}')

echo "CPU Utilization: ${cpu_val}% -> $status"

