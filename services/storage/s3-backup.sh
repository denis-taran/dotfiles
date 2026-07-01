#!/usr/bin/env bash
set -euo pipefail
umask 077

CRED_DIR="$CREDENTIALS_DIRECTORY"
AWS_ACCESS_KEY_ID="$(<"$CRED_DIR/s3-access-key")"
AWS_SECRET_ACCESS_KEY="$(<"$CRED_DIR/s3-secret-key")"
AWS_DEFAULT_REGION="$(<"$CRED_DIR/s3-region")"
export AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_DEFAULT_REGION

ENCRYPTION_PUB_KEY="$(<"$CRED_DIR/encryption-pub-key")"

BACKUP_DIR="$HOME/Backups/S3"
mkdir -p "$BACKUP_DIR"
chmod 700 "$BACKUP_DIR"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

buckets="$(aws s3api list-buckets --query 'Buckets[].Name' --output text)"

for bucket in $buckets; do
    echo "Syncing bucket: $bucket"
    aws s3 sync "s3://$bucket" "$TMP_DIR/$bucket" --quiet
done

FILENAME="$(date +'%Y-%m-%dT%H-%M-%S').zip.age"
TMP_FILE="$BACKUP_DIR/$FILENAME.tmp"

(cd "$TMP_DIR" && zip -1 -r -q - .) |
    age -r "$ENCRYPTION_PUB_KEY" -o "$TMP_FILE"

mv "$TMP_FILE" "$BACKUP_DIR/$FILENAME"
echo "Backup saved to $BACKUP_DIR/$FILENAME"

ARCHIVE="$BACKUP_DIR/$FILENAME"
par2create -q -n1 -r10 "$ARCHIVE.par2" "$ARCHIVE" >/dev/null
rm -f -- "$ARCHIVE.par2"
mv -- "$ARCHIVE".vol*.par2 "$ARCHIVE.par2"
echo "Recovery data saved to $ARCHIVE.par2"
