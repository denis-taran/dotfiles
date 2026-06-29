#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UNIT_DIR="/etc/systemd/system"
CRED_DIR="/etc/credstore"
LIBEXEC_DIR="/usr/local/libexec/dotfiles"

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

echo "Enter backup encryption key:"
store_encryption_pub_key code-encryption-pub-key

sudo install -d -o root -g root -m 0755 "$LIBEXEC_DIR"
sudo install -o root -g root -m 0755 "$SCRIPT_DIR/code-backup.sh" "$LIBEXEC_DIR/"
sudo install -o root -g root -m 0755 "$SCRIPT_DIR/code-cleanup.sh" "$LIBEXEC_DIR/"

sudo cp "$SCRIPT_DIR/code-backup@.service" "$UNIT_DIR/"
sudo cp "$SCRIPT_DIR/code-backup@.timer" "$UNIT_DIR/"

sudo systemctl daemon-reload
sudo systemctl enable --now "code-backup@$USER.timer"

echo "System timer installed for user $USER. Credentials stored in $CRED_DIR."
