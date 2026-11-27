#!/usr/bin/env bash

set -euo pipefail

environments=("development" "testing" "staging" "production")

for dir in "${environments[@]}"; do
    if mkdir -p -- "$dir"; then
        echo "Created or ensured: $dir"
    else
        echo "Error: Failed to create '$dir'." >&2
        exit 1
    fi
done

echo "--- Verification ---"
failures=0

for dir in "${environments[@]}"; do
    if [ -d "$dir" ]; then
        echo "VERIFIED: '$dir' exists."
    else
        echo "FAILED:   '$dir' is missing or not a directory." >&2
        failures=$((failures + 1))
    fi
done

if [ "$failures" -gt 0 ]; then
    echo "Verification failed for $failures directory(ies)." >&2
    exit 1
fi

echo "All directories created and verified successfully."
