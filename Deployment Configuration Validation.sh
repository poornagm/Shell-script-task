#!/usr/bin/env bash
set -euo pipefail

# -----------------------------------------------------------------------------
# Pre-Deployment Configuration Validation Script
# -----------------------------------------------------------------------------
# Customize these arrays via environment variables or edit defaults directly:
#   REQUIRED_VARS   : Mandatory environment variable names
#   REQUIRED_FILES  : Mandatory configuration file paths
#   REQUIRED_PORTS  : TCP ports that must be free and valid (1..65535)
#   WRITABLE_DIRS   : Directories that must exist and be readable/writable/traversable
#   READABLE_DIRS   : Directories that must exist and be readable/traversable
# -----------------------------------------------------------------------------

IFS=' ' read -r -a REQUIRED_VARS <<< "${REQUIRED_VARS:-APP_ENV APP_PORT DB_HOST DB_NAME DB_USER}"
IFS=' ' read -r -a REQUIRED_FILES <<< "${REQUIRED_FILES:-./config/app.conf ./config/settings.json}"
IFS=' ' read -r -a REQUIRED_PORTS <<< "${REQUIRED_PORTS:-${APP_PORT:-8080}}"
IFS=' ' read -r -a WRITABLE_DIRS <<< "${WRITABLE_DIRS:-./logs ./data ./tmp}"
IFS=' ' read -r -a READABLE_DIRS <<< "${READABLE_DIRS:-./config}"

ENV_FILE="${1:-}"
FAILED_CHECKS=0
PASSED_CHECKS=0

# Optionally load a .env file before validating environment variables
if [[ -n "$ENV_FILE" ]]; then
    if [[ ! -f "$ENV_FILE" || ! -r "$ENV_FILE" ]]; then
        echo "[FAIL] Specified environment file '$ENV_FILE' does not exist or is not readable." >&2
        exit 1
    fi
    set -a
    # shellcheck disable=SC1090
    source "$ENV_FILE"
    set +a
fi

log_pass() {
    PASSED_CHECKS=$(( PASSED_CHECKS + 1 ))
    printf '[PASS] %s\n' "$1"
}

log_fail() {
    FAILED_CHECKS=$(( FAILED_CHECKS + 1 ))
    printf '[FAIL] %s\n' "$1" >&2
}

is_port_in_use() {
    local port="$1"

    if command -v ss >/dev/null 2>&1; then
        ss -H -ltn "sport = :${port}" 2>/dev/null | grep -q .
        return $?
    elif command -v lsof >/dev/null 2>&1; then
        lsof -iTCP:"${port}" -sTCP:LISTEN -Pn >/dev/null 2>&1
        return $?
    elif command -v netstat >/dev/null 2>&1; then
        netstat -ltn 2>/dev/null | awk '{print $4}' | grep -Eq "[:.]${port}$"
        return $?
    else
        # Fallback: attempt TCP connection via /dev/tcp
        (echo >/dev/tcp/127.0.0.1/"$port") >/dev/null 2>&1
        return $?
    fi
}

validate_env_vars() {
    printf '\n--- 1. Validating Mandatory Environment Variables ---\n'
    for var_name in "${REQUIRED_VARS[@]}"; do
        if [[ -z "${!var_name:-}" ]]; then
            log_fail "Environment variable '${var_name}' is unset or empty."
        else
            log_pass "Environment variable '${var_name}' is set."
        fi
    done
}

validate_config_files() {
    printf '\n--- 2. Validating Configuration Files ---\n'
    for cfg in "${REQUIRED_FILES[@]}"; do
        if [[ ! -e "$cfg" ]]; then
            log_fail "Config file '${cfg}' does not exist."
            continue
        fi
        if [[ ! -f "$cfg" ]]; then
            log_fail "Config path '${cfg}' is not a regular file."
            continue
        fi
        if [[ ! -r "$cfg" ]]; then
            log_fail "Config file '${cfg}' is not readable by user '$(id -un)'."
            continue
        fi
        if [[ ! -s "$cfg" ]]; then
            log_fail "Config file '${cfg}' is empty (0 bytes)."
            continue
        fi

        # Optional syntax check for JSON files if python3 or jq is available
        if [[ "$cfg" == *.json ]]; then
            if command -v jq >/dev/null 2>&1; then
                if ! jq empty "$cfg" >/dev/null 2>&1; then
                    log_fail "JSON syntax error in '${cfg}'."
                    continue
                fi
            elif command -v python3 >/dev/null 2>&1; then
                if ! python3 -m json.tool "$cfg" >/dev/null 2>&1; then
                    log_fail "JSON syntax error in '${cfg}'."
                    continue
                fi
            fi
        fi

        log_pass "Config file '${cfg}' exists, is readable, and is non-empty."
    done
}

validate_ports() {
    printf '\n--- 3. Validating Application Ports ---\n'
    for port in "${REQUIRED_PORTS[@]}"; do
        if ! [[ "$port" =~ ^[1-9][0-9]*$ ]] || (( port > 65535 )); then
            log_fail "Port '${port}' is not a valid TCP port (1-65535)."
            continue
        fi

        if (( port < 1024 )) && [[ "$(id -u)" -ne 0 ]]; then
            log_fail "Privileged port '${port}' (<1024) requires root or CAP_NET_BIND_SERVICE."
            continue
        fi

        if is_port_in_use "$port"; then
            log_fail "Port '${port}' is already bound by another listening process."
        else
            log_pass "Port '${port}' is valid and available."
        fi
    done
}

validate_directories() {
    printf '\n--- 4. Validating Directory Permissions ---\n'

    for dir in "${READABLE_DIRS[@]}"; do
        if [[ ! -d "$dir" ]]; then
            log_fail "Readable directory '${dir}' does not exist."
        elif [[ ! -r "$dir" || ! -x "$dir" ]]; then
            log_fail "Directory '${dir}' lacks read/execute (r-x) permissions for '$(id -un)'."
        else
            log_pass "Directory '${dir}' exists and is readable/traversable (r-x)."
        fi
    done

    for dir in "${WRITABLE_DIRS[@]}"; do
        if [[ ! -d "$dir" ]]; then
            log_fail "Writable directory '${dir}' does not exist."
        elif [[ ! -r "$dir" || ! -w "$dir" || ! -x "$dir" ]]; then
            log_fail "Directory '${dir}' lacks full read/write/execute (rwx) permissions for '$(id -un)'."
        else
            log_pass "Directory '${dir}' exists and is readable/writable/traversable (rwx)."
        fi
    done
}

printf '============================================================\n'
printf 'PRE-DEPLOYMENT CONFIGURATION VALIDATION\n'
printf 'Host: %s | User: %s | Time: %s\n' \
    "$(hostname -f 2>/dev/null || hostname)" \
    "$(id -un)" \
    "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
printf '============================================================\n'

validate_env_vars
validate_config_files
validate_ports
validate_directories

printf '\n============================================================\n'
printf 'Validation Summary: %d passed, %d failed\n' "$PASSED_CHECKS" "$FAILED_CHECKS"
printf '============================================================\n'

if (( FAILED_CHECKS > 0 )); then
    printf '[ABORT] Deployment halted due to %d failed mandatory validation check(s).\n' "$FAILED_CHECKS" >&2
    exit 1
fi

printf '[READY] All mandatory pre-deployment checks passed. Proceeding with deployment.\n'
exit 0
