#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/setup-common.sh"

ensure_credstore
ensure_backup_dir "Database"

echo "Enter database credentials:"
read -rp "  Host: " db_host
read -rp "  Port: " db_port
read -rp "  Database: " db_name
read -rp "  Username: " db_user
read -rsp "  Password: " db_password
echo

write_credential db-host "$db_host"
write_credential db-port "$db_port"
write_credential db-name "$db_name"
write_credential db-user "$db_user"

pgpass_escape() {
    local value="$1"
    value="${value//\\/\\\\}"
    value="${value//:/\\:}"
    printf '%s' "$value"
}

printf -v db_pgpass '%s:%s:%s:%s:%s' \
    "$(pgpass_escape "$db_host")" \
    "$(pgpass_escape "$db_port")" \
    "$(pgpass_escape "$db_name")" \
    "$(pgpass_escape "$db_user")" \
    "$(pgpass_escape "$db_password")"
write_credential db-pgpass "$db_pgpass"
unset db_password db_pgpass

# Remove the superseded raw-password credential after the pgpass credential exists.
sudo rm -f -- "$CRED_DIR/db-password"

echo "Enter backup encryption key:"
store_encryption_pub_key db-encryption-pub-key

install_payload "$SCRIPT_DIR/db-backup.sh" "$SCRIPT_DIR/db-cleanup.sh"
install_units "$SCRIPT_DIR" db-backup
