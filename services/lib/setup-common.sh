# shellcheck shell=bash
# Helpers for the per-service setup-timer.sh scripts.

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UNIT_DIR="/etc/systemd/system"
CRED_DIR="/etc/credstore"
LIBEXEC_DIR="/usr/local/libexec/dotfiles"

TARGET_USER="${SUDO_USER:-$(id -un)}"
if ! passwd_entry="$(getent passwd "$TARGET_USER")"; then
    echo "Could not find the account for $TARGET_USER." >&2
    exit 1
fi
IFS=: read -r TARGET_USER _ target_uid _ _ TARGET_HOME _ <<<"$passwd_entry"
unset passwd_entry
if [[ "$target_uid" == 0 ]]; then
    echo "Run this as your normal user (not root); it calls sudo itself." >&2
    exit 1
fi
unset target_uid
if [[ "$TARGET_HOME" != /* ]]; then
    echo "Could not determine an absolute home directory for $TARGET_USER." >&2
    exit 1
fi

ensure_credstore() {
    sudo install -d -m 700 "$CRED_DIR"
}

# Create a persistent destination before systemd bind-mounts it into the sandbox.
ensure_backup_dir() {
    local name="${1:?backup directory name required}"
    sudo -u "$TARGET_USER" -H install -d -m 0700 "$TARGET_HOME/Backups"
    sudo -u "$TARGET_USER" -H install -d -m 0700 "$TARGET_HOME/Backups/$name"
}

write_credential() {
    local name="$1" val="$2"
    printf '%s' "$val" | sudo tee "$CRED_DIR/$name" >/dev/null
    sudo chmod 600 "$CRED_DIR/$name"
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
    write_credential "$name" "$val"
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

# Escape a value embedded inside a double-quoted systemd setting.
escape_unit_string() {
    local value="$1"
    value="${value//\\/\\\\}"
    value="${value//\"/\\\"}"
    value="${value//%/%%}"
    printf '%s' "$value"
}

# Render the account-specific service and append the common sandbox settings.
render_service_unit() {
    local source="$1" unit_user unit_home line
    unit_user="$TARGET_USER"
    unit_home="$(escape_unit_string "$TARGET_HOME")"

    while IFS= read -r line || [[ -n "$line" ]]; do
        if [[ "$line" == *"@TARGET_USER@"* ]]; then
            line="${line%%@TARGET_USER@*}${unit_user}${line#*@TARGET_USER@}"
        fi
        if [[ "$line" == *"@TARGET_HOME@"* ]]; then
            line="${line%%@TARGET_HOME@*}${unit_home}${line#*@TARGET_HOME@}"
        fi
        printf '%s\n' "$line"
    done <"$source"

    cat "$LIB_DIR/sandbox.conf"
}

# install_units <script-dir> <unit-base>  -- renders regular units and enables the timer
install_units() {
    local script_dir="$1" base="$2"

    render_service_unit "$script_dir/$base.service.in" |
        sudo tee "$UNIT_DIR/$base.service" >/dev/null
    sudo chmod 0644 "$UNIT_DIR/$base.service"
    sudo install -o root -g root -m 0644 "$script_dir/$base.timer" \
        "$UNIT_DIR/$base.timer"

    sudo systemctl daemon-reload
    sudo systemctl enable --now "$base.timer"

    echo "System timer installed for $TARGET_USER ($TARGET_HOME). Credentials stored in $CRED_DIR."
}
