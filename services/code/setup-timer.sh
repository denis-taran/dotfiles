#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/setup-common.sh"

ensure_credstore
ensure_backup_dir "Code"

echo "Enter backup encryption key:"
store_encryption_pub_key code-encryption-pub-key

install_payload "$SCRIPT_DIR/code-backup.sh" "$SCRIPT_DIR/code-cleanup.sh"
install_units "$SCRIPT_DIR" code-backup
