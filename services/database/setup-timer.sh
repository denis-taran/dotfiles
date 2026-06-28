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

store_encryption_pub_key() {
    local name="$1" val
    while :; do
        read -rp "  encryption public key (age1... or ssh-ed25519/ssh-rsa): " val
        case "$val" in
        age1* | ssh-ed25519\ * | ssh-rsa\ *) break ;;
        *) echo "  Invalid key — expected age1... or an SSH public key." >&2 ;;
        esac
    done
    printf '%s' "$val" | sudo tee "$CRED_DIR/$name" >/dev/null
    sudo chmod 600 "$CRED_DIR/$name"
}

sudo install -d -m 700 "$CRED_DIR"

echo "Enter database credentials:"
store_credential db-host "Host"
store_credential db-port "Port"
store_credential db-name "Database"
store_credential db-user "Username"
store_credential db-password "Password" true

echo "Enter backup encryption key:"
store_encryption_pub_key db-encryption-pub-key

sudo cp "$SCRIPT_DIR/db-backup@.service" "$UNIT_DIR/"
sudo cp "$SCRIPT_DIR/db-backup@.timer" "$UNIT_DIR/"

sudo systemctl daemon-reload
sudo systemctl enable --now "db-backup@$USER.timer"

echo "System timer installed for user $USER. Credentials stored in $CRED_DIR."
