#!/usr/bin/env bash
set -euo pipefail

umask 077

CRED_DIR="$CREDENTIALS_DIRECTORY"
DB_HOST="$(<"$CRED_DIR/db-host")"
DB_PORT="$(<"$CRED_DIR/db-port")"
DB_NAME="$(<"$CRED_DIR/db-name")"
DB_USER="$(<"$CRED_DIR/db-user")"
ENCRYPTION_PUB_KEY="$(<"$CRED_DIR/encryption-pub-key")"

PGPASSWORD="$(<"$CRED_DIR/db-password")"
export PGPASSWORD
export PGSSLMODE=verify-full
export PGSSLROOTCERT=/etc/ssl/certs/ca-certificates.crt

BACKUP_DIR="$HOME/Backups/Database"
mkdir -p "$BACKUP_DIR"
chmod 700 "$BACKUP_DIR"

FILENAME="$(date +'%Y-%m-%dT%H-%M-%S').dump.age"
TMP_FILE="$BACKUP_DIR/$FILENAME.tmp"

pg_dump -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" \
    -d "$DB_NAME" -F c -b |
    age -r "$ENCRYPTION_PUB_KEY" -o "$TMP_FILE"

mv "$TMP_FILE" "$BACKUP_DIR/$FILENAME"
echo "Backup saved to $BACKUP_DIR/$FILENAME"

ARCHIVE="$BACKUP_DIR/$FILENAME"
par2create -q -n1 -r10 "$ARCHIVE.par2" "$ARCHIVE" >/dev/null
rm -f -- "$ARCHIVE.par2"
mv -- "$ARCHIVE".vol*.par2 "$ARCHIVE.par2"
echo "Recovery data saved to $ARCHIVE.par2"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
"$SCRIPT_DIR/db-cleanup.sh" "$BACKUP_DIR"
