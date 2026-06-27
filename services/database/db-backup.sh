#!/usr/bin/env bash
set -euo pipefail

CRED_DIR="$CREDENTIALS_DIRECTORY"
DB_HOST="$(<"$CRED_DIR/db-host")"
DB_PORT="$(<"$CRED_DIR/db-port")"
DB_NAME="$(<"$CRED_DIR/db-name")"
DB_USER="$(<"$CRED_DIR/db-user")"

PGPASSWORD="$(<"$CRED_DIR/db-password")"
export PGPASSWORD
export PGSSLMODE=verify-full
export PGSSLROOTCERT=/etc/ssl/certs/ca-certificates.crt

BACKUP_DIR="$HOME/Backups/Database"
mkdir -p "$BACKUP_DIR"

FILENAME="$(date +'%Y-%m-%dT%H-%M-%S').dump"
TMP_FILE="$BACKUP_DIR/$FILENAME.tmp"

pg_dump -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" \
    -d "$DB_NAME" -F c -b -f "$TMP_FILE"

mv "$TMP_FILE" "$BACKUP_DIR/$FILENAME"
echo "Backup saved to $BACKUP_DIR/$FILENAME"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
"$SCRIPT_DIR/db-cleanup.sh" "$BACKUP_DIR"
