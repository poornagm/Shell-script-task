#!/usr/bin/env bash

set -euo pipefail

usage() {
    cat <<EOF
Usage: $(basename "$0") <username> <environment>

Arguments:
  username     Target Linux/application username
  environment  Target environment (e.g., development, testing, staging, production)

Example:
  $(basename "$0") deploy_user staging
EOF
}

if [ "$#" -lt 2 ]; then
    echo "Error: Both <username> and <environment> are required." >&2
    echo "" >&2
    usage >&2
    exit 1
fi

if [ "$#" -gt 2 ]; then
    echo "Error: Too many arguments provided (expected 2, got $#)." >&2
    echo "" >&2
    usage >&2
    exit 1
fi

username="$1"
environment="$2"

if [ -z "$username" ] || [ -z "$environment" ]; then
    echo "Error: Arguments cannot be empty strings." >&2
    echo "" >&2
    usage >&2
    exit 1
fi

echo "Username:    $username"
echo "Environment: $environment"
