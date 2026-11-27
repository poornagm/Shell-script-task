#!/usr/bin/env bash
set -euo pipefail
servers=("web-srv-01" "web-srv-02" "app-srv-01" "db-srv-01" "cache-srv-01")
for i in "${!servers[@]}"; do
    printf "Index %d: %s\n" "$i" "${servers[$i]}"
done
