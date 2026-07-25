#!/usr/bin/env bash
set -euo pipefail

BACKUP_DIR="${1:?Usage: gmail-cleanup.sh <backup-dir>}"

current_ym=$((10#$(date +'%Y') * 12 + 10#$(date +'%m')))

declare -A kept_month kept_year

shopt -s nullglob
for file in "$BACKUP_DIR"/*.zip.age; do
    basename="$(basename "$file")"
    year="${basename:0:4}"
    month="${basename:5:2}"

    file_ym=$((10#$year * 12 + 10#$month))
    age=$((current_ym - file_ym))

    if ((age <= 1)); then
        # keep every backup we make in the current and prev. month
        continue
    elif ((age <= 6)); then
        # keep only one backup per month if it is 2 - 6 months old
        key="$year-$month"
        if [[ -n "${kept_month[$key]:-}" ]]; then
            rm -f -- "$file" "$file.par2"
            echo "Removed old backup: $basename"
        else
            kept_month[$key]=1
        fi
    else
        # keep one backup per year when it's older than 6 months
        if [[ -n "${kept_year[$year]:-}" ]]; then
            rm -f -- "$file" "$file.par2"
            echo "Removed old backup: $basename"
        else
            kept_year[$year]=1
        fi
    fi
done
