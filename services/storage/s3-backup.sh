#!/usr/bin/env bash
set -euo pipefail

CRED_DIR="$CREDENTIALS_DIRECTORY"
export AWS_ACCESS_KEY_ID="$(<"$CRED_DIR/s3-access-key")"
export AWS_SECRET_ACCESS_KEY="$(<"$CRED_DIR/s3-secret-key")"
export AWS_DEFAULT_REGION="$(<"$CRED_DIR/s3-region")"
export PATH="/snap/bin:$PATH"

BACKUP_DIR="$HOME/Backups/S3"
mkdir -p "$BACKUP_DIR"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

buckets="$(aws s3api list-buckets --query 'Buckets[].Name' --output text)"

for bucket in $buckets; do
    echo "Syncing bucket: $bucket"
    aws s3 sync "s3://$bucket" "$TMP_DIR/$bucket" --quiet
done

FILENAME="$(date +'%Y-%m-%dT%H-%M-%S').zip"
TMP_FILE="$BACKUP_DIR/$FILENAME.tmp"

(cd "$TMP_DIR" && zip -1 -r -q "$TMP_FILE" .)

mv "$TMP_FILE" "$BACKUP_DIR/$FILENAME"
echo "Backup saved to $BACKUP_DIR/$FILENAME"
