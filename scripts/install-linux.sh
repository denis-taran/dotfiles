#!/bin/bash

set -Eeuo pipefail
umask 022
trap 'echo "failed at line $LINENO: $BASH_COMMAND" >&2' ERR

readonly _KIND_VERSION="v0.31.0"
readonly _KUBECTL_VERSION="v1.33.0"
readonly _YQ_VERSION="v4.53.2"
readonly _ANSIBLE_VERSION="13.6.0"
readonly _DOTNET_SDK_VERSION="10.0"
NODE_SNAP_CHANNEL="24/stable"

declare -Ar _KIND_SHA256=(
    [amd64]="eb244cbafcc157dff60cf68693c14c9a75c4e6e6fedaf9cd71c58117cb93e3fa"
    [arm64]="8e1014e87c34901cc422a1445866835d1e666f2a61301c27e722bdeab5a1f7e4"
)

declare -Ar _KUBECTL_SHA256=(
    [amd64]="9efe8d3facb23e1618cba36fb1c4e15ac9dc3ed5a2c2e18109e4a66b2bac12dc"
    [arm64]="48541d119455ac5bcc5043275ccda792371e0b112483aa0b29378439cf6322b9"
)

declare -A _YQ_SHA256=(
    [amd64]="d56bf5c6819e8e696340c312bd70f849dc1678a7cda9c2ad63eebd906371d56b"
    [arm64]="03061b2a50c7a498de2bbb92d7cb078ce433011f085a4994117c2726be4106ea"
)

readonly _SUPPORTED_MS_CODENAMES="noble resolute"
readonly _SUPPORTED_HC_CODENAMES="noble resolute"

# GPG fingerprints for APT repo signing keys
readonly _MICROSOFT_GPG_FP="BC528686B50D79E339D3721CEB3E94ADBE1229CF"
readonly _MICROSOFT_2025_GPG_FP="AA86F75E427A19DD33346403EE4D7792F748182B"
readonly _HELM_GPG_FP="DDF78C3E6EBB2D2CC223C95C62BA89D07698DBC6"
readonly _TERRAFORM_GPG_FP="798AEC654E5C15428C8E42EEAA16FCBCA621E701"
readonly _1PASSWORD_GPG_FP="3FEF9748469ADBE15DA7CA80AC2D62742012EA22"
readonly _CLAUDE_GPG_FP="31DDDE24DDFAB679F42D7BD2BAA929FF1A7ECACE"

_is_root=false
[ "$EUID" -eq 0 ] && _is_root=true
if ! $_is_root; then
    echo "Not running as root: package installation will be skipped."
fi

if $_is_root; then
    USERNAME="${SUDO_USER:-}"
    if [[ -z "$USERNAME" ]]; then
        read -r -p "Enter the username to configure: " USERNAME
    fi
    if [[ ! "$USERNAME" =~ ^[a-z_][a-z0-9_-]*[$]?$ ]]; then
        echo "ERROR: '$USERNAME' is not a valid Linux username" >&2
        exit 1
    fi
    HOMEDIR="$(getent passwd "$USERNAME" | cut -d: -f6)"
    if [[ -z "$HOMEDIR" ]]; then
        echo "no home dir for '$USERNAME'" >&2
        exit 1
    fi
else
    USERNAME="${USER:-}"
    HOMEDIR="${HOME:-}"
    if [[ -z "$USERNAME" || -z "$HOMEDIR" ]]; then
        echo "Could not determine user or home directory" >&2
        exit 1
    fi
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"

readonly USERNAME HOMEDIR SCRIPT_DIR

# shellcheck source=/dev/null
. /etc/os-release
_is_ubuntu=false
[[ "${ID:-}" == "ubuntu" ]] && _is_ubuntu=true
if ! $_is_ubuntu; then
    if $_is_root; then
        echo "only ubuntu is supported for full installation" >&2
        exit 1
    fi
    echo "Non-Ubuntu distro detected: package installation will be skipped."
fi

is_wsl() {
    grep -qi "microsoft" /proc/version 2>/dev/null
}

run_as_user() {
    if $_is_root; then
        sudo -u "$USERNAME" -H "$@"
    else
        "$@"
    fi
}

# owner arg sets chown on the link itself, not the target
create_link() {
    local target=$1
    local link=$2
    local owner=${3:-}
    local parent
    parent="$(dirname "$link")"
    local current_target

    if [ ! -d "$parent" ]; then
        if [[ -n "$owner" ]]; then
            sudo -u "$owner" -H mkdir -p "$parent" || {
                echo "Cannot create dir: $parent" >&2
                return 1
            }
        else
            mkdir -p "$parent" || {
                echo "Cannot create dir: $parent" >&2
                return 1
            }
        fi
    fi

    if [ ! -e "$target" ] && [ ! -L "$target" ]; then
        echo "Target does not exist: $target" >&2
        return 1
    fi

    if [ -L "$link" ]; then
        current_target=$(readlink "$link" || true)
        if [ "$current_target" = "$target" ]; then
            echo "Link already exists: $link -> $target"
            return 0
        fi
    fi

    if [[ -d "$link" && ! -L "$link" ]]; then
        echo "Refusing to replace real directory at '$link'" >&2
        return 1
    elif [[ -e "$link" || -L "$link" ]]; then
        rm -f -- "$link"
    fi

    ln -sfnT -- "$target" "$link"

    if [ -n "$owner" ]; then
        chown -h "$owner:" "$link"
    fi

    echo "Created link: $link -> $target"
}

run_as_user mkdir -p "$HOMEDIR/.config"
run_as_user touch "$HOMEDIR/.hushlogin"

if $_is_ubuntu && $_is_root; then
    apt-get update

    DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a apt-get -o DPkg::Lock::Timeout=300 install -y --no-install-recommends \
        ca-certificates \
        curl \
        gnupg \
        jq \
        openssl \
        software-properties-common \
        xdg-user-dirs

    add-apt-repository -y universe
    apt-get update

    update-ca-certificates

    packages=(
        "aardvark-dns"
        "bash-completion"
        "bat"
        "bind9-dnsutils"
        "build-essential"
        "direnv"
        "eza"
        "fd-find"
        "fzf"
        "git-delta"
        "gh"
        "git-lfs"
        "git"
        "htop"
        "iproute2"
        "lsof"
        "iptables"
        "locales"
        "lsb-release"
        "neovim"
        "netavark"
        "pandoc"
        "postgresql-client"
        "passt"
        "pipx"
        "podman-compose"
        "podman"
        "python-is-python3"
        "python3-full"
        "python3-venv"
        "rename"
        "ripgrep"
        "shellcheck"
        "shfmt"
        "snapd"
        "tealdeer"
        "tmux"
        "uidmap"
        "unzip"
        "xmlstarlet"
        "yamllint"
        "zip"
        "zoxide"
    )

    if ! is_wsl; then
        packages=( "${packages[@]/aardvark-dns}" )
        packages=( "${packages[@]/netavark}" )
    fi

    DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a apt-get -o DPkg::Lock::Timeout=300 install -y --no-install-recommends "${packages[@]}"
    apt-get clean

    locale-gen en_US.UTF-8
    update-locale LANG=en_US.UTF-8

    sudo -u "$USERNAME" -H git lfs install

    snap list aws-cli >/dev/null 2>&1 || snap install aws-cli --classic
    snap list node >/dev/null 2>&1 || snap install node --classic --channel="$NODE_SNAP_CHANNEL"

    # pipx becuase the ansible PPA is perpetually broken on new ubuntu releases
    if sudo -u "$USERNAME" -H bash -c 'pipx list --json 2>/dev/null | jq -e ".venvs | has(\"ansible\")" >/dev/null'; then
        echo "ansible already installed via pipx. Skipping."
    else
        sudo -u "$USERNAME" -H bash -c "pipx install --include-deps 'ansible==${_ANSIBLE_VERSION}'"
    fi
    sudo -u "$USERNAME" -H pipx ensurepath

    # enable lingering so rootless podman services start without login
    if ! is_wsl; then
        loginctl enable-linger "$USERNAME"
    fi

    # enable socket-activated podman API so commands work immediately
    if [[ -f /usr/lib/systemd/user/podman.socket ]]; then
        run_as_user mkdir -p "$HOMEDIR/.config/systemd/user/sockets.target.wants"
        create_link /usr/lib/systemd/user/podman.socket \
            "$HOMEDIR/.config/systemd/user/sockets.target.wants/podman.socket" \
            "$USERNAME"
    fi
fi

declare -A links=(
    ["$SCRIPT_DIR/.bash_profile"]="$HOMEDIR/.bash_profile"
    ["$SCRIPT_DIR/.bashrc"]="$HOMEDIR/.bashrc"
    ["$SCRIPT_DIR/.profile"]="$HOMEDIR/.profile"
    ["$SCRIPT_DIR/.config/git/config"]="$HOMEDIR/.config/git/config"
    ["$SCRIPT_DIR/.config/git/ignore"]="$HOMEDIR/.config/git/ignore"
    ["$SCRIPT_DIR/.config/git/attributes"]="$HOMEDIR/.config/git/attributes"
    ["$SCRIPT_DIR/.config/git/delta"]="$HOMEDIR/.config/git/delta"
    ["$SCRIPT_DIR/.inputrc"]="$HOMEDIR/.inputrc"
    ["$SCRIPT_DIR/.config/nvim/init.lua"]="$HOMEDIR/.config/nvim/init.lua"
    ["$SCRIPT_DIR/.editorconfig"]="$HOMEDIR/.editorconfig"
)

_link_owner=""
if $_is_root; then _link_owner="$USERNAME"; fi

run_as_user mkdir -p "$HOMEDIR/.ssh"
$_is_root && chown "$USERNAME:" "$HOMEDIR/.ssh" || true
chmod 700 "$HOMEDIR/.ssh"

if is_wsl; then
    if [[ -z "${USERPROFILE:-}" ]]; then
        echo "USERPROFILE not set" >&2
        exit 1
    fi
    _win_ssh="$USERPROFILE/.ssh"
    if [[ ! -d "$_win_ssh" ]]; then
        echo "Windows ~/.ssh not found at $_win_ssh" >&2
        exit 1
    fi
    for _f in "$_win_ssh"/*; do
        [[ -f "$_f" ]] || continue
        _name="$(basename "$_f")"
        run_as_user cp "$_f" "$HOMEDIR/.ssh/$_name"
        chmod 600 "$HOMEDIR/.ssh/$_name"
    done
fi
for src in "${!links[@]}"; do
    dest="${links[$src]}"
    run_as_user mkdir -p "$(dirname "$dest")"
    create_link "$src" "$dest" "${_link_owner:-}"
done

if is_wsl; then
    if [[ ! -d "$USERPROFILE" || -L "$USERPROFILE" ]]; then
        echo "Windows user dir not found. Skipping." >&2
    else
        declare -A wsl_links=(
            ["$USERPROFILE/Backups"]="$HOMEDIR/Backups"
            ["$USERPROFILE/Desktop"]="$HOMEDIR/Desktop"
            ["$USERPROFILE/Downloads"]="$HOMEDIR/Downloads"
            ["$USERPROFILE/Proton"]="$HOMEDIR/Proton"
        )

        for _wsl_target in "${!wsl_links[@]}"; do
            _wsl_dest="${wsl_links[$_wsl_target]}"
            create_link "$_wsl_target" "$_wsl_dest" "${_link_owner:-}" || continue
        done
    fi
fi

command -v xdg-user-dirs-update >/dev/null 2>&1 && run_as_user xdg-user-dirs-update

install_env_vars() {
    local env_file="$HOMEDIR/.env.sh"
    local env_json="$SCRIPT_DIR/env.json"

    [[ -f "$env_json" ]] || return 0

    run_as_user touch "$env_file"
    chmod 600 "$env_file"

    local name value
    while IFS=$'\t' read -r name value; do
        if ! grep -q "^export ${name}=" "$env_file"; then
            printf 'export %s="%s"\n' "$name" "$value" >>"$env_file"
        fi
    done < <(jq -r '.[] | [.name, .value] | @tsv' "$env_json")
}

install_env_vars

_git_cfg="$HOMEDIR/.config/git/local"
_allowed_signers="$HOMEDIR/.config/git/allowed_signers"

run_as_user mkdir -p "$HOMEDIR/.config/git"
run_as_user touch "$_git_cfg"
chmod 600 "$_git_cfg"

_git_cfg_list=$(git config -f "$_git_cfg" --list 2>/dev/null || true)

if [[ "$_git_cfg_list" != *"user.name="* || "$_git_cfg_list" != *"user.email="* ]]; then
    GIT_NAME="${GIT_AUTHOR_NAME:-}"
    GIT_EMAIL="${GIT_AUTHOR_EMAIL:-}"
    [[ -z "$GIT_NAME" ]] && read -r -p "Enter your Git full name: " GIT_NAME
    [[ -z "$GIT_EMAIL" ]] && read -r -p "Enter your Git email address: " GIT_EMAIL
    [[ "$GIT_EMAIL" != *@*.* ]] && {
        echo "git email looks wrong" >&2
        exit 1
    }
    run_as_user git config -f "$_git_cfg" user.name "$GIT_NAME"
    run_as_user git config -f "$_git_cfg" user.email "$GIT_EMAIL"
else
    GIT_EMAIL=$(grep '^user\.email=' <<<"$_git_cfg_list" | cut -d= -f2-)
fi

if [[ "$_git_cfg_list" != *"user.signingkey="* ]]; then
    GIT_SSH_KEY="${GIT_SSH_SIGNING_KEY:-}"
    [[ -z "$GIT_SSH_KEY" ]] && read -r -p "SSH public key for commit signing (blank to skip): " GIT_SSH_KEY
    if [[ -n "$GIT_SSH_KEY" ]]; then
        [[ "${GIT_SSH_KEY%% *}" != ssh-* ]] && {
            echo "not an SSH public key (must start with ssh-)" >&2
            exit 1
        }
        run_as_user git config -f "$_git_cfg" \
            user.signingkey "$GIT_SSH_KEY"
        run_as_user git config -f "$_git_cfg" commit.gpgsign true
        run_as_user git config -f "$_git_cfg" gpg.format ssh
        run_as_user git config -f "$_git_cfg" gpg.ssh.allowedSignersFile "$_allowed_signers"
        echo "$GIT_EMAIL $GIT_SSH_KEY" | run_as_user tee "$_allowed_signers" >/dev/null
        chmod 600 "$_allowed_signers"
    fi
fi

if command -v code &>/dev/null; then
    _ext_file="$SCRIPT_DIR/.config/Code/User/extensions.txt"
    if [[ -f "$_ext_file" ]]; then
        while IFS= read -r ext; do
            [[ -z "$ext" || "$ext" == \#* ]] && continue
            run_as_user code --install-extension "$ext" --force 2>/dev/null || true
        done < "$_ext_file"
    fi
    run_as_user git config -f "$_git_cfg" core.editor "code --wait"
elif command -v nvim &>/dev/null; then
    run_as_user git config -f "$_git_cfg" core.editor "nvim"
elif command -v vim &>/dev/null; then
    run_as_user git config -f "$_git_cfg" core.editor "vim"
else
    run_as_user git config -f "$_git_cfg" core.editor "vi"
fi

apt_key() {
    local url=$1
    local keyring_file=$2
    local supported_codenames=${3:-}
    local expected_fingerprint=${4:-}
    local keyring_dir
    keyring_dir="$(dirname "$keyring_file")"
    install -m 0755 -d "$keyring_dir"

    local check_keyring="$keyring_file"
    if [[ ! -f "$keyring_file" ]]; then
        local tmp_keyring
        tmp_keyring=$(mktemp --suffix=.gpg)
        trap 'rm -f "$tmp_keyring"; trap - RETURN' RETURN
        curl -fsSL "$url" | gpg --batch --yes --dearmor -o "$tmp_keyring"
        check_keyring="$tmp_keyring"
    fi

    if [[ -n "$expected_fingerprint" ]]; then
        local _kn
        _kn="$(basename "$keyring_file")"
        if ! gpg --no-default-keyring --keyring "$check_keyring" \
            --with-colons --fingerprint 2>/dev/null |
            awk -F: '$1=="fpr"{print $10}' |
            grep -qi "^${expected_fingerprint}$"; then
            echo "fingerprint mismatch in $_kn: $expected_fingerprint" >&2
            return 1
        fi
    fi

    if [[ "$check_keyring" != "$keyring_file" ]]; then
        install -m 644 "$check_keyring" "$keyring_file"
    fi

    if [[ -n "$supported_codenames" ]]; then
        local codename="$VERSION_CODENAME"
        if [[ " $supported_codenames " != *" $codename "* ]]; then
            echo "No repo release for '$codename'." \
                "Update supported_codenames in install-linux.sh." >&2
            return 1
        fi
        echo "$codename"
    fi
}

download_and_install_binary() {
    local url="$1"
    local expected_sha="$2"
    local dest="$3"
    local name
    name="$(basename "$dest")"

    local dlfile
    dlfile=$(mktemp)
    trap 'rm -f "$dlfile"; trap - RETURN' RETURN
    # follow redirects as GitHub release URLs do a 302 to S3
    curl -fsSL -o "$dlfile" "$url"
    local actual_sha
    actual_sha=$(sha256sum "$dlfile" | awk '{print $1}')
    if [[ "$actual_sha" != "$expected_sha" ]]; then
        echo "bad sha: $name" >&2
        return 1
    fi
    install -m 0755 "$dlfile" "$dest"
}

if $_is_ubuntu && $_is_root; then
    _arch=$(dpkg --print-architecture)
    [[  "$_arch" == "amd64" || "$_arch" == "arm64" ]] || {
        echo "unsupported arch: $_arch" >&2
        exit 1
    }

    # azcli snap is community-published
    _codename=$(apt_key "https://packages.microsoft.com/keys/microsoft.asc" "/etc/apt/keyrings/microsoft.gpg" \
        "$_SUPPORTED_MS_CODENAMES" "$_MICROSOFT_GPG_FP")
    printf 'deb [arch=%s signed-by=/etc/apt/keyrings/microsoft.gpg] https://packages.microsoft.com/repos/azure-cli/ %s main\n' \
        "$_arch" "${_codename/resolute/noble}" >/etc/apt/sources.list.d/azure-cli.list

    # dotnet uses a separate 2025 MS key
    apt_key "https://packages.microsoft.com/keys/microsoft-2025.asc" \
        "/etc/apt/keyrings/microsoft-2025.gpg" \
        "" "$_MICROSOFT_2025_GPG_FP" >/dev/null
    printf 'deb [arch=%s signed-by=/etc/apt/keyrings/microsoft-2025.gpg] https://packages.microsoft.com/ubuntu/%s/prod %s main\n' \
        "$_arch" "$VERSION_ID" "$_codename" >/etc/apt/sources.list.d/dotnet.list

    apt_key "https://packages.buildkite.com/helm-linux/helm-debian/gpgkey" "/usr/share/keyrings/helm.gpg" \
        "" "$_HELM_GPG_FP"
    printf 'deb [signed-by=/usr/share/keyrings/helm.gpg] https://packages.buildkite.com/helm-linux/helm-debian/any/ any main\n' \
        >/etc/apt/sources.list.d/helm.list

    _hc_codename=$(apt_key "https://apt.releases.hashicorp.com/gpg" \
        "/usr/share/keyrings/hashicorp-archive-keyring.gpg" \
        "$_SUPPORTED_HC_CODENAMES" "$_TERRAFORM_GPG_FP")
    # terraform is only in the test channel on recent ubuntu
    printf 'deb [arch=%s signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com %s test\n' \
        "$_arch" "$_hc_codename" >/etc/apt/sources.list.d/hashicorp.list

    apt_key "https://downloads.claude.ai/keys/claude-code.asc" \
        "/etc/apt/keyrings/claude-code.gpg" \
        "" "$_CLAUDE_GPG_FP" >/dev/null
    printf 'deb [arch=%s signed-by=/etc/apt/keyrings/claude-code.gpg] https://downloads.claude.ai/claude-code/apt/stable stable main\n' \
        "$_arch" >/etc/apt/sources.list.d/claude-code.list

    apt-get update

    DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a apt-get -o DPkg::Lock::Timeout=300 install -y --no-install-recommends \
        azure-cli claude-code helm "dotnet-sdk-${_DOTNET_SDK_VERSION}" terraform

    if ! is_wsl; then
        apt_key "https://downloads.1password.com/linux/keys/1password.asc" \
            "/usr/share/keyrings/1password-archive-keyring.gpg" \
            "" "$_1PASSWORD_GPG_FP" >/dev/null
        printf 'deb [arch=%s signed-by=/usr/share/keyrings/1password-archive-keyring.gpg] https://downloads.1password.com/linux/debian/%s stable main\n' \
            "$_arch" "$_arch" >/etc/apt/sources.list.d/1password.list
        apt-get update
        DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a apt-get -o DPkg::Lock::Timeout=300 install -y --no-install-recommends \
            1password-cli
    fi
    apt-get clean

    download_and_install_binary \
        "https://github.com/kubernetes-sigs/kind/releases/download/${_KIND_VERSION}/kind-linux-$_arch" \
        "${_KIND_SHA256[$_arch]}" /usr/local/bin/kind

    download_and_install_binary \
        "https://dl.k8s.io/release/${_KUBECTL_VERSION}/bin/linux/$_arch/kubectl" \
        "${_KUBECTL_SHA256[$_arch]}" /usr/local/bin/kubectl

    download_and_install_binary \
        "https://github.com/mikefarah/yq/releases/download/${_YQ_VERSION}/yq_linux_$_arch" \
        "${_YQ_SHA256[$_arch]}" /usr/local/bin/yq

    ln -sfnT /usr/bin/batcat /usr/local/bin/bat
    ln -sfnT /usr/bin/fdfind /usr/local/bin/fd

    echo "net.ipv4.ip_forward=1" >/etc/sysctl.d/99-ip-forward.conf
    sysctl -w net.ipv4.ip_forward=1

    if is_wsl; then
        systemctl mask tmp.mount

        # rootless podman needs / as a shared mount; WSL2 defaults to private
        cat >/etc/systemd/system/wsl-rshared.service <<'UNIT'
[Unit]
Description=Make / a shared mount for rootless containers
DefaultDependencies=no
Before=local-fs.target

[Service]
Type=oneshot
ExecStart=/bin/mount --make-rshared /

[Install]
WantedBy=local-fs.target
UNIT
        systemctl enable wsl-rshared.service
    fi

    # runs kind as regular user with rootless podman
    _kind_as_user() {
        local uid
        uid=$(id -u "$USERNAME")
        if is_wsl; then
            sudo -u "$USERNAME" -H env KIND_EXPERIMENTAL_PROVIDER=podman NETAVARK_FW=iptables kind "$@"
        else
            sudo -u "$USERNAME" -H \
                env XDG_RUNTIME_DIR="/run/user/$uid" \
                    DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$uid/bus" \
                    KIND_EXPERIMENTAL_PROVIDER=podman \
                systemd-run --scope --user -p Delegate=yes kind "$@"
        fi
    }

    if _kind_as_user get clusters 2>/dev/null | grep -q "^kind$"; then
        echo "kind cluster already exists. Skipping creation."
    else
        if is_wsl; then
            [[ -e /usr/sbin/iptables-legacy ]] && update-alternatives --set iptables /usr/sbin/iptables-legacy
            [[ -e /usr/sbin/ip6tables-legacy ]] && update-alternatives --set ip6tables /usr/sbin/ip6tables-legacy
            sudo -u "$USERNAME" -H podman network rm kind 2>/dev/null || true
            sudo -u "$USERNAME" -H podman network create --ipv6=false kind
        fi
        _kind_as_user create cluster
    fi

    kube_dir="$HOMEDIR/.kube"
    sudo -u "$USERNAME" -H mkdir -p "$kube_dir"

    user_cfg="$kube_dir/config"
    tmp_kind_cfg=$(mktemp)
    tmp_merged=""
    trap 'rm -f "$tmp_kind_cfg" ${tmp_merged:+"$tmp_merged"}' EXIT

    _kind_as_user get kubeconfig >"$tmp_kind_cfg"
    chown "$USERNAME" "$tmp_kind_cfg"

    if [[ -f "$user_cfg" ]]; then
        tmp_merged=$(mktemp)
        sudo -u "$USERNAME" -H env "KUBECONFIG=${tmp_kind_cfg}:${user_cfg}" kubectl config view --flatten >"$tmp_merged"
        install -m 0600 -o "$USERNAME" -g "$(id -gn "$USERNAME")" "$tmp_merged" "$user_cfg"
    else
        install -m 0600 -o "$USERNAME" -g "$(id -gn "$USERNAME")" "$tmp_kind_cfg" "$user_cfg"
    fi

    sudo -u "$USERNAME" -H kubectl config use-context kind-kind
fi
