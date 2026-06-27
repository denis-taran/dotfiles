#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UNIT_DIR="/etc/systemd/system"
CRED_DIR="/etc/credstore"

store_credential() {
    local name="$1" prompt="$2" secret="${3:-false}"
    local val
    if [[ "$secret" == true ]]; then
        read -rsp "  $prompt: " val
        echo
    else
        read -rp "  $prompt: " val
    fi
    printf '%s' "$val" | sudo tee "$CRED_DIR/$name" >/dev/null
    sudo chmod 600 "$CRED_DIR/$name"
}

sudo mkdir -p "$CRED_DIR"

echo "Enter database credentials:"
store_credential db-host "Host"
store_credential db-port "Port"
store_credential db-name "Database"
store_credential db-user "Username"
store_credential db-password "Password" true

sudo cp "$SCRIPT_DIR/db-backup@.service" "$UNIT_DIR/"
sudo cp "$SCRIPT_DIR/db-backup@.timer" "$UNIT_DIR/"

sudo systemctl daemon-reload
sudo systemctl enable --now "db-backup@$USER.timer"

echo "System timer installed for user $USER. Credentials stored in $CRED_DIR."
