#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UNIT_DIR="/etc/systemd/system"
CRED_DIR="/etc/credstore"
LIBEXEC_DIR="/usr/local/libexec/dotfiles"

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

sudo install -d -m 700 "$CRED_DIR"

echo "Enter Clockify credentials:"
store_credential clockify-api-key "API key" true
store_credential clockify-workspace-id "Workspace ID"
store_credential clockify-user-id "User ID"

sudo install -d -o root -g root -m 0755 "$LIBEXEC_DIR"
sudo install -o root -g root -m 0644 "$SCRIPT_DIR/clockify-backup.py" "$LIBEXEC_DIR/"

sudo cp "$SCRIPT_DIR/clockify-backup@.service" "$UNIT_DIR/"
sudo cp "$SCRIPT_DIR/clockify-backup@.timer" "$UNIT_DIR/"

sudo systemctl daemon-reload
sudo systemctl enable --now "clockify-backup@$USER.timer"

echo "System timer installed for user $USER. Credentials stored in $CRED_DIR."
