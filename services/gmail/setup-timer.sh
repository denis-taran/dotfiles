#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/setup-common.sh"

ensure_credstore

echo "Enter Gmail credentials:"
store_credential gmail-user "Gmail address"
store_credential gmail-app-password "App password" true

echo "Enter backup encryption key:"
store_encryption_pub_key gmail-encryption-pub-key

install_payload "$SCRIPT_DIR/gmail-backup.sh" "$SCRIPT_DIR/gmail-cleanup.sh"
install_units "$SCRIPT_DIR" gmail-backup
