#!/usr/bin/env bash
set -euo pipefail

# -----------------------------------------------------------------------------
# Interactive Service Management Menu (Allowlist & Authorization Enforced)
# -----------------------------------------------------------------------------
# Space-separated allowlist of approved test services (override via env var if needed)
IFS=' ' read -r -a APPROVED_SERVICES <<< "${APPROVED_SERVICES:-nginx apache2 postgresql docker cron ssh}"
AUDIT_LOG="${AUDIT_LOG:-/tmp/service_menu_audit.log}"

# -----------------------------------------------------------------------------
# Authorization Check: Require root or sudo privileges
# -----------------------------------------------------------------------------
if [[ "$(id -u)" -ne 0 ]]; then
    if command -v sudo >/dev/null 2>&1 && sudo -n true 2>/dev/null; then
        SUDO="sudo"
    else
        echo "[DENIED] Authorization failed: Run this script as root or with sudo privileges." >&2
        exit 1
    fi
else
    SUDO=""
fi

if ! command -v systemctl >/dev/null 2>&1; then
    echo "[ERROR] 'systemctl' is not available on this system." >&2
    exit 2
fi

log_audit() {
    local action="$1"
    local service="$2"
    local result="$3"
    local actor="${SUDO_USER:-$(id -un)}"
    printf '[%s] user=%s action=%s service=%s result=%s\n' \
        "$(date -u '+\%Y-\%m-\%dT\%H:\%M:\%SZ')" "$actor" "$action" "$service" "$result" >> "$AUDIT_LOG" 2>/dev/null || true
}

is_service_approved() {
    local candidate="$1"
    for svc in "${APPROVED_SERVICES[@]}"; do
        if [[ "$svc" == "$candidate" ]]; then
            return 0
        fi
    done
    return 1
}

select_approved_service() {
    local choice=""
    local max="${#APPROVED_SERVICES[@]}"

    while true; do
        printf '\nApproved Test Services:\n'
        for i in "${!APPROVED_SERVICES[@]}"; do
            printf '  %d)
