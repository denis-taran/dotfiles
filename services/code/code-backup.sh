#!/usr/bin/env bash
set -euo pipefail

umask 077

CRED_DIR="$CREDENTIALS_DIRECTORY"
ENCRYPTION_PUB_KEY="$(<"$CRED_DIR/encryption-pub-key")"

SOURCE_DIR="$HOME/Code"
BACKUP_DIR="$HOME/Backups/Code"
mkdir -p "$BACKUP_DIR"
chmod 700 "$BACKUP_DIR"

FILENAME="$(date +'%Y-%m-%d').zip.age"
STAGING_DIR="$(mktemp -d "$BACKUP_DIR/.code-backup.XXXXXX")"
trap 'rm -rf -- "$STAGING_DIR"' EXIT
TMP_FILE="$STAGING_DIR/$FILENAME"

(cd "$SOURCE_DIR" && zip -9 -r -q - .) |
    age -r "$ENCRYPTION_PUB_KEY" -o "$TMP_FILE"

mv "$TMP_FILE" "$BACKUP_DIR/$FILENAME"
echo "Backup saved to $BACKUP_DIR/$FILENAME"

ARCHIVE="$BACKUP_DIR/$FILENAME"
par2create -q -n1 -r10 "$ARCHIVE.par2" "$ARCHIVE" >/dev/null
rm -f -- "$ARCHIVE.par2"
mv -- "$ARCHIVE".vol*.par2 "$ARCHIVE.par2"
echo "Recovery data saved to $ARCHIVE.par2"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
"$SCRIPT_DIR/code-cleanup.sh" "$BACKUP_DIR"
