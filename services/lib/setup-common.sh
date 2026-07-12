# shellcheck shell=bash
# Helpers for the per-service setup-timer.sh scripts.

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UNIT_DIR="/etc/systemd/system"
CRED_DIR="/etc/credstore"
LIBEXEC_DIR="/usr/local/libexec/dotfiles"

TARGET_USER="${SUDO_USER:-$USER}"
if [[ "$TARGET_USER" == root ]]; then
    echo "Run this as your normal user (not root); it calls sudo itself." >&2
    exit 1
fi

ensure_credstore() {
    sudo install -d -m 700 "$CRED_DIR"
}

# Create a persistent destination before systemd bind-mounts it into the sandbox.
ensure_backup_dir() {
    local name="${1:?backup directory name required}"
    local target_home
    target_home="$(getent passwd "$TARGET_USER" | cut -d: -f6)"
    if [[ -z "$target_home" ]]; then
        echo "Could not find the home directory for $TARGET_USER." >&2
        return 1
    fi
    sudo -u "$TARGET_USER" -H install -d -m 0700 "$target_home/Backups"
    sudo -u "$TARGET_USER" -H install -d -m 0700 "$target_home/Backups/$name"
}

# store_credential <name> <prompt> [secret] -- secret=true hides input
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

# store_encryption_pub_key <name>   -- validates an age/SSH public key before storing
store_encryption_pub_key() {
    local name="$1" val
    while :; do
        read -rp "  encryption public key (age1... or ssh-ed25519/ssh-rsa): " val
        case "$val" in
        age1* | ssh-ed25519\ * | ssh-rsa\ *) break ;;
        *) echo "  Invalid key, expected age1... or an SSH public key." >&2 ;;
        esac
    done
    printf '%s' "$val" | sudo tee "$CRED_DIR/$name" >/dev/null
    sudo chmod 600 "$CRED_DIR/$name"
}

# install_payload <file>...  -- into $LIBEXEC_DIR; .py as 0644, rest 0755
install_payload() {
    sudo install -d -o root -g root -m 0755 "$LIBEXEC_DIR"
    local file mode
    for file in "$@"; do
        case "$file" in
        *.py) mode=0644 ;;
        *) mode=0755 ;;
        esac
        sudo install -o root -g root -m "$mode" "$file" "$LIBEXEC_DIR/"
    done
}

# install_units <script-dir> <unit-base>  -- installs the @.service/@.timer and enables it
install_units() {
    local script_dir="$1" base="$2"
    # Concatenate fresh each run (unit + shared sandbox) so re-running stays idempotent.
    cat "$script_dir/$base@.service" "$LIB_DIR/sandbox.conf" |
        sudo tee "$UNIT_DIR/$base@.service" >/dev/null
    sudo cp "$script_dir/$base@.timer" "$UNIT_DIR/"

    sudo systemctl daemon-reload
    sudo systemctl enable --now "$base@$TARGET_USER.timer"

    echo "System timer installed for user $TARGET_USER. Credentials stored in $CRED_DIR."
}
