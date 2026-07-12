#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/setup-common.sh"

ensure_credstore
ensure_backup_dir "Clockify"

echo "Enter Clockify credentials:"
store_credential clockify-api-key "API key" true
store_credential clockify-workspace-id "Workspace ID"
store_credential clockify-user-id "User ID"

install_payload "$SCRIPT_DIR/clockify-backup.py"
install_units "$SCRIPT_DIR" clockify-backup
