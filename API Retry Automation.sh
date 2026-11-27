#!/usr/bin/env bash
set -euo pipefail

# -----------------------------------------------------------------------------
# Configurable Defaults (can be overridden via CLI flags or environment vars)
# -----------------------------------------------------------------------------
URL="${URL:-}"
METHOD="${METHOD:-GET}"
MAX_RETRIES="${MAX_RETRIES:-5}"          # Up to 5 retry attempts after initial try
DELAY_SECONDS="${DELAY_SECONDS:-3}"      # Base delay in seconds between retries
BACKOFF="${BACKOFF:-false}"              # true for exponential backoff, false for fixed delay
TIMEOUT_SECONDS="${TIMEOUT_SECONDS:-10}"
BODY="${BODY:-}"
HEADERS=()

usage() {
    cat <<EOF
Usage: $0 -u <url> [options]

Options:
  -u <url>        Target HTTP/HTTPS endpoint URL (required)
  -X <method>     HTTP method: GET, POST, PUT, PATCH, DELETE (default: GET)
  -H <header>     Custom header, e.g., "Authorization: Bearer TOKEN" (repeatable)
  -d <data>       Request
