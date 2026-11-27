#!/usr/bin/env bash
set -euo pipefail

# -----------------------------------------------------------------------------
# Automated Directory Backup Script
# -----------------------------------------------------------------------------
SOURCE_DIR="${1:-}"
BACKUP_DEST="${2:-}"

usage() {
    cat <<EOF
Usage: $0 <source_directory> <backup_destination_directory>

Arguments:
  <source_directory>              Directory to archive and compress (required)
  <backup_destination_directory>  Target directory where the archive is stored (required)

Example:
  $0 /etc/nginx /var/backups/nginx
EOF
    exit 1
}

if [[ -z "$SOURCE_DIR" \vert{}\vert{} -z "$BACKUP_DEST" ]]; then
    echo "Error: Both <source_directory> and <backup_destination_directory> are required." >&2
    usage
fi

if [[ ! -d "$SOURCE_DIR" ]]; then
    echo "Error: Source directory '$SOURCE_DIR' does not exist or is not a directory." >&2
    exit 2
fi

if [[ ! -r "$SOURCE_DIR" ]]; then
    echo "Error: Source directory '$SOURCE_DIR' is not readable." >&2
    exit 2
fi

# Create destination directory if it does not exist and verify write access
if [[ ! -d "$BACKUP_DEST" ]]; then
    mkdir -p "$BACKUP_DEST" 2>/dev/null || {
        echo "Error: Failed to create backup destination '$BACKUP_DEST'." >&2
        exit 2
    }
fi

if [[ ! -w "$BACKUP_DEST" ]]; then
    echo "Error: Backup destination '$BACKUP_DEST' is not writable." >&2
    exit 2
fi

# Resolve canonical paths to prevent archiving the backup destination inside itself
abs_source="$(cd "$SOURCE_DIR" && pwd -P)"
abs_dest="$(cd "$BACKUP_DEST" && pwd -P)"

if [[ "$abs_dest" == "$abs_source" || "$abs_dest" == "$abs_source"/* ]]; then
    echo "Error: Backup destination ('$abs_dest')
