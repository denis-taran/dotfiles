#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/setup-common.sh"

ensure_credstore
ensure_backup_dir "Database"

echo "Enter database credentials:"
store_credential db-host "Host"
store_credential db-port "Port"
store_credential db-name "Database"
store_credential db-user "Username"
store_credential db-password "Password" true

echo "Enter backup encryption key:"
store_encryption_pub_key db-encryption-pub-key

install_payload "$SCRIPT_DIR/db-backup.sh" "$SCRIPT_DIR/db-cleanup.sh"
install_units "$SCRIPT_DIR" db-backup
