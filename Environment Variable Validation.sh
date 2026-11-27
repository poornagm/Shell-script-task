#!/bin/sh
# Exit immediately if a command exits with a non-zero status
set -e
# 1. Read APP_PORT and assign a default (e.g., 8080) if unset or empty
PORT="${APP_PORT:-8080}"

# 2. Validate APP_ENV
case "${APP_ENV}" in
    dev|qa|prod)
        ;;
    "")
        echo "Error: APP_ENV environment variable is not set or is empty." >&2
        echo "Allowed values: dev, qa, prod" >&2
        exit 1
        ;;
    *)
        echo "Error: Invalid APP_ENV '${APP_ENV}'." >&2
        echo "Allowed values: dev, qa, prod" >&2
        exit 1
        ;;
esac

# 3. Output the validated configuration
echo "Configuration validated successfully:"
echo "  Environment: ${APP_ENV}"
echo "  Port:        ${PORT}"

# Add your application startup command below
# e.g., exec ./my-app --env="${APP_ENV}" --port="${PORT}"
