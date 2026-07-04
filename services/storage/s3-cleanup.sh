#!/usr/bin/env bash
set -euo pipefail

BACKUP_DIR="${1:?Usage: s3-cleanup.sh <backup-dir>}"

current_ym=$((10#$(date +'%Y') * 12 + 10#$(date +'%m')))

declare -A kept_year

shopt -s nullglob
for file in "$BACKUP_DIR"/*.zip.age; do
    basename="$(basename "$file")"
    year="${basename:0:4}"
    month="${basename:5:2}"

    file_ym=$((10#$year * 12 + 10#$month))
    age=$((current_ym - file_ym))

    if ((age <= 6)); then
        # keep every backup from the last 6 months
        continue
    else
        # keep one backup per year when older than 6 months
        if [[ -n "${kept_year[$year]:-}" ]]; then
            rm -f -- "$file" "$file.par2"
            echo "Removed old backup: $basename"
        else
            kept_year[$year]=1
        fi
    fi
done
