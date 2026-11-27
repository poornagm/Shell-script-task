#!/usr/bin/env bash
set -euo pipefail
for ((i = 1; i <= 30; i++)); do
    if ((i == 25)); then
        echo "Reached 25 — stopping loop."
        break
    fi

    if ((i % 3 == 0)); then
        continue
    fi

    echo "$i"
done
