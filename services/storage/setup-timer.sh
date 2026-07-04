#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/setup-common.sh"

ensure_credstore

echo "Enter AWS credentials:"
store_credential s3-access-key "Access Key ID"
store_credential s3-secret-key "Secret Access Key" true
store_credential s3-region "Region (e.g. us-east-1)"

echo "Enter backup encryption key:"
store_encryption_pub_key s3-encryption-pub-key

install_payload "$SCRIPT_DIR/s3-backup.sh"
install_units "$SCRIPT_DIR" s3-backup
