#!/usr/bin/env bash
set -euo pipefail

BACKUP_DIR="${1:?Usage: code-cleanup.sh <backup-dir>}"

current_ym=$(( 10#$(date +'%Y') * 12 + 10#$(date +'%m') ))

declare -A kept_month kept_year

shopt -s nullglob
for file in "$BACKUP_DIR"/*.zip.age; do
    basename="$(basename "$file")"
    year="${basename:0:4}"
    month="${basename:5:2}"

    file_ym=$(( 10#$year * 12 + 10#$month ))
    age=$(( current_ym - file_ym ))

    if (( age <= 1 )); then
        # keep every backup in the current and prev. month
        continue
    elif (( age <= 6 )); then
        # keep one backup per month when it's 2 - 6 months old
        key="$year-$month"
        if [[ -n "${kept_month[$key]:-}" ]]; then
            rm "$file"
            echo "Removed old backup: $basename"
        else
            kept_month[$key]=1
        fi
    else
        # keep one backup per year when older than 6 months
        if [[ -n "${kept_year[$year]:-}" ]]; then
            rm "$file"
            echo "Removed old backup: $basename"
        else
            kept_year[$year]=1
        fi
    fi
done
