#!/usr/bin/env bash
set -euo pipefail

# -----------------------------------------------------------------------------
# SSL/TLS Certificate Expiry Monitoring Script
# -----------------------------------------------------------------------------
DOMAIN="${1:-}"
PORT="${2:-443}"
WARN_DAYS="${3:-30}"
TIMEOUT_SECONDS="${TIMEOUT_SECONDS:-10}"

usage() {
    cat <<EOF
Usage: $0 <domain_name> [port] [warn_days]

Arguments:
  <domain_name>   Target domain or hostname (required, e.g., example.com)
  [port]          TLS port (default: 443)
  [warn_days]     Warning threshold in days (default: 30)

Environment overrides:
  TIMEOUT_SECONDS Connection timeout in seconds (default: 10)

Example:
  $0 github.com
  $0 internal.example.com 8443 30
EOF
    exit 1
}

if [[ -z "$DOMAIN" ]]; then
    echo "Error: Domain name is required." >&2
    usage
fi

# Strip accidental scheme or trailing path if the user pasted a URL
DOMAIN="${DOMAIN#https://}"
DOMAIN="${DOMAIN#http://}"
DOMAIN="${DOMAIN%%/*}"

if ! [[ "$PORT" =~ ^[1-9][0-9]*$ ]] || (( PORT > 65535 )); then
    echo "Error: Invalid port '$PORT'." >&2
    exit 1
fi

if ! [[ "$WARN_DAYS" =~ ^[0-9]+$ ]]; then
    echo "Error: [warn_days] must be a non-negative integer." >&2
    exit 1
fi

for cmd in openssl date; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "Error: Required command '$cmd' is not installed." >&2
        exit 2
    fi
done

# Retrieve leaf certificate via SNI
cert_pem="$(
    timeout "$TIMEOUT_SECONDS" openssl s_client \
        -servername "$DOMAIN" \
        -connect "${DOMAIN}:${PORT}" \
        </dev/null 2>/dev/null \
    | openssl x509 2>/dev/null
)" || true

if [[ -z "$cert_pem" ]]; then
    echo "Error: Unable to retrieve TLS certificate from ${DOMAIN}:${PORT}." >&2
    exit 2
fi

# Extract subject, issuer, and notAfter date
subject="$(printf '%s\n' "$cert_pem" | openssl x509 -noout -subject | sed 's/^subject=[[:space:]]*//')"
issuer="$(printf '%s\n' "$cert_pem" | openssl x509 -noout -issuer | sed 's/^issuer=[[:space:]]*//')"
not_after_raw="$(printf '%s\n' "$cert_pem" | openssl x509 -noout -enddate | cut -d'=' -f2-)"

# Convert expiration date to Unix epoch (supports GNU date and BSD/macOS date)
if expiry_epoch="$(date -u -d "$not_after_raw" '+%s' 2>/dev/null)"; then
    :
elif expiry_epoch="$(date -u -j -f "%b %e %T %Y %Z" "$not_after_raw" '+%s' 2>/dev/null)"; then
    :
else
    echo "Error: Could not parse certificate expiry timestamp '${not_after_raw}'." >&2
    exit 2
fi

now_epoch="$(date -u '+%s')"
seconds_remaining=$(( expiry_epoch - now_epoch ))
days_remaining=$(( seconds_remaining / 86400 ))
expiry_utc="$(date -u -d "@$expiry_epoch" '+%Y-%m-%d %H:%M:%S UTC' 2>/dev/null || date -u -r "$expiry_epoch" '+%Y-%m-%d %H:%M:%S UTC')"

printf 'TLS Certificate Report for %s:%s\n' "$DOMAIN" "$PORT"
printf '==================================================\n'
printf 'Subject        : %s\n' "$subject"
printf 'Issuer         : %s\n' "$issuer"
printf 'Expires On     : %s\n' "$expiry_utc"
printf 'Days Remaining : %d day(s)\n' "$days_remaining"
printf 'Threshold      : %d day(s)\n' "$WARN_DAYS"
printf '==================================================\n'

if (( seconds_remaining <= 0 )); then
    printf '[CRITICAL] TLS certificate for %s:%s HAS EXPIRED (%d days ago)!\n' \
        "$DOMAIN" "$PORT" "$(( -days_remaining ))" >&2
    exit 2
elif (( days_remaining <= WARN_DAYS )); then
    printf '[WARNING] TLS certificate for %s:%s expires in %d day(s) (within %d-day threshold)!\n' \
        "$DOMAIN" "$PORT" "$days_remaining" "$WARN_DAYS" >&2
    exit 1
else
    printf '[OK] TLS certificate for %s:%s is valid for %d more day(s).\n' \
        "$DOMAIN" "$PORT" "$days_remaining"
    exit 0
fi
