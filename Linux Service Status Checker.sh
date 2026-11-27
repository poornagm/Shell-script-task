#!/usr/bin/env bash

set -euo pipefail

if ! command -v systemctl >/dev/null 2>&1; then
    echo "Error: systemctl is not available on this system." >&2
    exit 1
fi

printf "Enter the service name: "
read -r service_name

if [ -z "$service_name" ]; then
    echo "Error: No service name entered." >&2
    exit 1
fi

# Normalize unit name (append .service if no unit suffix is provided)
case "$service_name" in
    *.*) unit="$service_name" ;;
    *)   unit="${service_name}.service" ;;
esac

# Check whether the unit exists on the system
load_state=$(systemctl show -p LoadState --value -- "$unit" 2>/dev/null || true)
if [ -z "$load_state" ] || [ "$load_state" = "not-found" ]; then
    echo "Error: '$unit' is not a valid or installed systemd service (LoadState: not-found)." >&2
    exit 2
fi

# Query active state (active, inactive, failed, activating, deactivating, etc.)
active_state=$(systemctl is-active -- "$unit" 2>/dev/null || true)

echo "Service: $unit"
echo "Status:  ${active_state:-unknown}"

if [ "$active_state" = "active" ]; then
    exit 0
else
    exit 1
fi
