#!/usr/bin/env bash
set -euo pipefail

BACKUP_DIR="${1:?Usage: db-cleanup.sh <backup-dir>}"

current_month="$(date +'%Y-%m')"
previous_month="$(date -d '1 month ago' +'%Y-%m')"

shopt -s nullglob
for file in "$BACKUP_DIR"/*.dump; do
    basename="$(basename "$file")"
    file_month="${basename:0:7}"

    [[ "$file_month" == "$current_month" || "$file_month" == "$previous_month" ]] && continue

    file_day="${basename:8:2}"
    if [[ "$file_day" != "01" ]]; then
        rm "$file"
        echo "Removed old backup: $basename"
    fi
done
