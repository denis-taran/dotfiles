#!/usr/bin/env bash
set -euo pipefail

umask 077

CRED_DIR="$CREDENTIALS_DIRECTORY"
GMAIL_USER="$(<"$CRED_DIR/gmail-user")"
ENCRYPTION_PUB_KEY="$(<"$CRED_DIR/encryption-pub-key")"

BACKUP_DIR="$HOME/Backups/Email"
mkdir -p "$BACKUP_DIR"
chmod 700 "$BACKUP_DIR"

WORK_DIR="$(mktemp -d)"
trap 'rm -rf -- "$WORK_DIR"' EXIT

MAILDIR="$WORK_DIR/mail"
mkdir -p "$MAILDIR"

cat >"$WORK_DIR/mbsyncrc" <<EOF
IMAPAccount gmail
Host imap.gmail.com
Port 993
User $GMAIL_USER
PassCmd "cat '$CRED_DIR/gmail-app-password'"
TLSType IMAPS
CertificateFile /etc/ssl/certs/ca-certificates.crt

IMAPStore gmail-remote
Account gmail

MaildirStore gmail-local
Path $MAILDIR/
Inbox $MAILDIR/Inbox
Subfolders Verbatim

Channel gmail
Far :gmail-remote:
Near :gmail-local:
Patterns "[Gmail]/All Mail"
Create Near
Sync Pull
SyncState *
EOF

mbsync -c "$WORK_DIR/mbsyncrc" gmail

FILENAME="$(date +'%Y-%m-%d').zip.age"
TMP_FILE="$BACKUP_DIR/$FILENAME.tmp"

(cd "$MAILDIR" && zip -9 -r -q - .) |
    age -r "$ENCRYPTION_PUB_KEY" -o "$TMP_FILE"

mv "$TMP_FILE" "$BACKUP_DIR/$FILENAME"
echo "Backup saved to $BACKUP_DIR/$FILENAME"

ARCHIVE="$BACKUP_DIR/$FILENAME"
par2create -q -n1 -r10 "$ARCHIVE.par2" "$ARCHIVE" >/dev/null
rm -f -- "$ARCHIVE.par2"
mv -- "$ARCHIVE".vol*.par2 "$ARCHIVE.par2"
echo "Recovery data saved to $ARCHIVE.par2"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
"$SCRIPT_DIR/gmail-cleanup.sh" "$BACKUP_DIR"
