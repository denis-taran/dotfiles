#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/setup-common.sh"

ensure_credstore

echo "Enter backup encryption key:"
store_encryption_pub_key cloud-encryption-pub-key

install_payload "$SCRIPT_DIR/cloud-backup.sh" "$SCRIPT_DIR/cloud-cleanup.sh"
install_units "$SCRIPT_DIR" cloud-backup
