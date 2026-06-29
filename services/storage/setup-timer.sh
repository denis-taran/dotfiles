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

echo "Enter AWS credentials:"
store_credential s3-access-key "Access Key ID"
store_credential s3-secret-key "Secret Access Key" true
store_credential s3-region "Region (e.g. us-east-1)"

echo "Enter backup encryption key:"
store_encryption_pub_key s3-encryption-pub-key

sudo install -d -o root -g root -m 0755 "$LIBEXEC_DIR"
sudo install -o root -g root -m 0755 "$SCRIPT_DIR/s3-backup.sh" "$LIBEXEC_DIR/"

sudo cp "$SCRIPT_DIR/s3-backup@.service" "$UNIT_DIR/"
sudo cp "$SCRIPT_DIR/s3-backup@.timer" "$UNIT_DIR/"

sudo systemctl daemon-reload
sudo systemctl enable --now "s3-backup@$USER.timer"

echo "System timer installed for user $USER. Credentials stored in $CRED_DIR."
