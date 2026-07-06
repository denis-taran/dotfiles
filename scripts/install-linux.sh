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
readonly _AWS_CLI_GPG_FP="FB5DB77FD5C118B80511ADA8A6310ACC4672475C"
readonly _GOOGLE_GPG_FP="EB4C1BFD4F042F6DDDCCEC917721F63BD38B4796"

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

run_as_user mkdir -p "$HOMEDIR/Code"
chmod 700 "$HOMEDIR/Code"

if ! is_wsl; then
    run_as_user mkdir -p "$HOMEDIR/Backups"
    chmod 700 "$HOMEDIR/Backups"
fi

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
        "age"
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
        "isync"
        "locales"
        "lsb-release"
        "neovim"
        "netavark"
        "pandoc"
        "par2"
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
        filtered=()
        for pkg in "${packages[@]}"; do
            case "$pkg" in
            aardvark-dns | netavark) continue ;;
            esac
            filtered+=("$pkg")
        done
        packages=("${filtered[@]}")
    fi

    DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a apt-get -o DPkg::Lock::Timeout=300 install -y --no-install-recommends "${packages[@]}"
    apt-get clean

    locale-gen en_US.UTF-8
    update-locale LANG=en_US.UTF-8

    sudo -u "$USERNAME" -H git lfs install

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

    # restart containers with restart-policy=always on boot (e.g. the kind cluster)
    if [[ -f /usr/lib/systemd/user/podman-restart.service ]]; then
        run_as_user mkdir -p "$HOMEDIR/.config/systemd/user/default.target.wants"
        create_link /usr/lib/systemd/user/podman-restart.service \
            "$HOMEDIR/.config/systemd/user/default.target.wants/podman-restart.service" \
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
if $_is_root; then chown "$USERNAME:" "$HOMEDIR/.ssh"; fi
chmod 700 "$HOMEDIR/.ssh"

get_windows_home() {
    local cmd='/mnt/c/Windows/System32/cmd.exe' win_profile

    [[ -x "$cmd" ]] || return 127

    win_profile="$(
        cd /mnt/c || exit 1
        "$cmd" /d /q /c 'echo %USERPROFILE%'
    )" || return 1
    win_profile="${win_profile%$'\r'}"

    [[ "$win_profile" =~ ^[A-Za-z]:\\ ]] || return 1

    wslpath -u "$win_profile"
}

USERPROFILE=""
if is_wsl; then
    USERPROFILE="$(get_windows_home || true)"
    if [[ -z "$USERPROFILE" ]]; then
        echo "Could not locate Windows user profile. Skipping Windows links and SSH import." >&2
    fi
fi

if is_wsl && [[ -n "$USERPROFILE" ]]; then
    _win_ssh="$USERPROFILE/.ssh"
    if [[ -d "$_win_ssh" ]]; then
        for _f in "$_win_ssh"/*; do
            [[ -f "$_f" ]] || continue
            _name="$(basename "$_f")"
            run_as_user cp "$_f" "$HOMEDIR/.ssh/$_name"
            chmod 600 "$HOMEDIR/.ssh/$_name"
        done
    else
        echo "Windows ~/.ssh not found at $_win_ssh. Skipping SSH import." >&2
    fi
fi

# Ensure a `gh` host alias for github.com
_ssh_config="$HOMEDIR/.ssh/config"
if ! run_as_user grep -qE '^Host[[:space:]]+gh([[:space:]]|$)' "$_ssh_config" 2>/dev/null; then
    printf '\nHost gh\n    HostName github.com\n    User git\n' |
        run_as_user tee -a "$_ssh_config" >/dev/null
    chmod 600 "$_ssh_config"
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

install_vscode_extensions() {
    command -v code &>/dev/null || return 0
    local _ext_file="$SCRIPT_DIR/.config/Code/User/extensions.txt"
    [[ -f "$_ext_file" ]] || return 0
    local ext
    while IFS= read -r ext; do
        [[ -z "$ext" || "$ext" == \#* ]] && continue
        run_as_user code --install-extension "$ext" --force 2>/dev/null || true
    done <"$_ext_file"
    run_as_user git config -f "$_git_cfg" core.editor "code --wait"
}

if command -v nvim &>/dev/null; then
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

verify_pgp_signature() {
    local keyfile="$1" sigfile="$2" target="$3" expected_fp="${4:-}"
    if [[ ! -f "$keyfile" ]]; then
        echo "public key not found: $keyfile" >&2
        return 1
    fi

    local gnupghome rc=0
    gnupghome=$(mktemp -d)
    chmod 700 "$gnupghome"

    GNUPGHOME="$gnupghome" gpg --batch --quiet --import "$keyfile" || rc=1

    if [[ $rc -eq 0 && -n "$expected_fp" ]]; then
        if ! GNUPGHOME="$gnupghome" gpg --batch --with-colons --fingerprint 2>/dev/null |
            awk -F: '$1=="fpr"{print $10}' |
            grep -qi "^${expected_fp}$"; then
            echo "fingerprint mismatch: expected $expected_fp" >&2
            rc=1
        fi
    fi

    if [[ $rc -eq 0 ]]; then
        GNUPGHOME="$gnupghome" gpg --batch --verify "$sigfile" "$target" || rc=1
    fi

    rm -rf "$gnupghome"
    return $rc
}

install_aws_cli() {
    local arch="$1"
    local arch_label
    case "$arch" in
    amd64) arch_label="x86_64" ;;
    arm64) arch_label="aarch64" ;;
    *)
        echo "unsupported arch for aws cli: $arch" >&2
        return 1
        ;;
    esac

    local keyfile="$SCRIPT_DIR/scripts/keys/aws-cli.asc"

    local workdir
    workdir=$(mktemp -d)
    trap 'rm -rf "$workdir"; trap - RETURN' RETURN

    local url="https://awscli.amazonaws.com/awscli-exe-linux-${arch_label}.zip"
    curl -fsSL -o "$workdir/awscliv2.zip" "$url"
    curl -fsSL -o "$workdir/awscliv2.sig" "$url.sig"

    if ! verify_pgp_signature "$keyfile" "$workdir/awscliv2.sig" \
        "$workdir/awscliv2.zip" "$_AWS_CLI_GPG_FP"; then
        echo "aws cli signature verification failed" >&2
        return 1
    fi

    unzip -q -o -d "$workdir" "$workdir/awscliv2.zip"

    "$workdir/aws/install" --bin-dir /usr/local/bin \
        --install-dir /usr/local/aws-cli --update
}

if $_is_ubuntu && $_is_root; then
    _arch=$(dpkg --print-architecture)
    [[ "$_arch" == "amd64" || "$_arch" == "arm64" ]] || {
        echo "unsupported arch: $_arch" >&2
        exit 1
    }

    install_aws_cli "$_arch"

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

    # runs podman as regular user with rootless env
    _podman_as_user() {
        if is_wsl; then
            sudo -u "$USERNAME" -H podman "$@"
        else
            sudo -u "$USERNAME" -H env XDG_RUNTIME_DIR="/run/user/$(id -u "$USERNAME")" podman "$@"
        fi
    }

    _kind_control_plane_running() {
        [[ "$(_podman_as_user inspect -f '{{.State.Running}}' kind-control-plane 2>/dev/null)" == "true" ]]
    }

    if _kind_as_user get clusters 2>/dev/null | grep -q "^kind$" && ! _kind_control_plane_running; then
        echo "kind cluster exists but its container isn't running. Recreating."
        _kind_as_user delete cluster 2>/dev/null || true
    fi

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

    _podman_as_user update --restart=always kind-control-plane

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
        sudo -u "$USERNAME" -H env "KUBECONFIG=${tmp_kind_cfg}:${user_cfg}" kubectl config view --flatten | tee "$tmp_merged" >/dev/null
        install -m 0600 -o "$USERNAME" -g "$(id -gn "$USERNAME")" "$tmp_merged" "$user_cfg"
    else
        install -m 0600 -o "$USERNAME" -g "$(id -gn "$USERNAME")" "$tmp_kind_cfg" "$user_cfg"
    fi

    sudo -u "$USERNAME" -H kubectl config use-context kind-kind
fi

###############################################################################
## Desktop Environment
###############################################################################

is_wsl && exit 1
systemctl get-default 2>/dev/null | grep -q 'graphical' || exit 1

echo "Desktop environment detected. GUI apps will be installed."

# needed for full disk encryption with TPM
DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a \
    apt-get -o DPkg::Lock::Timeout=300 install -y --no-install-recommends \
    tpm2-tss tpm2-tools

if [[ "$_arch" == "amd64" ]]; then
    apt_key \
        "https://dl.google.com/linux/linux_signing_key.pub" \
        "/etc/apt/keyrings/google-chrome.gpg" \
        "" "$_GOOGLE_GPG_FP" >/dev/null
    printf 'deb [arch=amd64 signed-by=/etc/apt/keyrings/google-chrome.gpg] http://dl.google.com/linux/chrome/deb/ stable main\n' \
        >/etc/apt/sources.list.d/google-chrome.list
fi

# reuses the microsoft.gpg keyring imported earlier for the azure-cli repo
printf 'deb [arch=amd64,arm64,armhf signed-by=/etc/apt/keyrings/microsoft.gpg] https://packages.microsoft.com/repos/code stable main\n' \
    >/etc/apt/sources.list.d/vscode.list

apt-get update

DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a \
    apt-get -o DPkg::Lock::Timeout=300 install -y --no-install-recommends \
    code fprintd libpam-fprintd

if [[ "$_arch" == "amd64" ]]; then
    # gnupg2 is required by 1password, otherwise its install fails
    DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a \
        apt-get -o DPkg::Lock::Timeout=300 install -y --no-install-recommends \
        gnupg2 google-chrome-stable 1password
fi

snap remove --purge firefox >/dev/null 2>&1 || true

apt-get clean

install_vscode_extensions

# fingerprint auth for polkit and sudo prompts
if dpkg -l libpam-fprintd 2>/dev/null | grep -q '^ii'; then
    _polkit_pam="/etc/pam.d/polkit-1"
    _polkit_src="/usr/lib/pam.d/polkit-1"
    if [[ ! -f "$_polkit_pam" && -f "$_polkit_src" ]]; then
        cp "$_polkit_src" "$_polkit_pam"
    fi

    for _pam_file in "$_polkit_pam" /etc/pam.d/sudo; do
        if [[ -f "$_pam_file" ]] && ! grep -q "pam_fprintd.so" "$_pam_file"; then
            sed -i \
                '/@include common-auth/i auth      sufficient  pam_fprintd.so' \
                "$_pam_file"
        fi
    done
fi

# currently obsidian is broken on ubuntu, because they switched to rust
# coreutils. so for now install it manually:
#   snap install obsidian --classic

run_as_user dbus-run-session -- bash <<'EOF' || true
set +e

# keyboard shortcuts
gsettings set org.gnome.shell.keybindings show-screenshot-ui "['<Super><Shift>s']"
gsettings set org.gnome.settings-daemon.plugins.media-keys home "['<Super>e']"
gsettings set org.gnome.settings-daemon.plugins.media-keys control-center "['<Super>i']"

# strip Ubuntu's GNOME customizations
gsettings set org.gnome.desktop.interface gtk-theme Adwaita
gsettings set org.gnome.desktop.interface icon-theme Adwaita
gsettings set org.gnome.desktop.interface cursor-theme Adwaita
gnome-extensions disable ubuntu-dock@ubuntu.com 2>/dev/null || true
gnome-extensions disable ding@rastersoft.com 2>/dev/null || true

# fonts
gsettings set org.gnome.desktop.interface font-name 'Frutiger Next Regular 11'
gsettings set org.gnome.desktop.wm.preferences titlebar-font 'Frutiger Next Bold 11'
gsettings set org.gnome.desktop.interface document-font-name 'Source Sans 3 Regular 11'
gsettings set org.gnome.desktop.interface monospace-font-name 'JetBrains Mono Regular 11'

# key repeat
gsettings set org.gnome.desktop.peripherals.keyboard delay 350
gsettings set org.gnome.desktop.peripherals.keyboard repeat true
gsettings set org.gnome.desktop.peripherals.keyboard repeat-interval 24
EOF

# install fonts
_fonts_dst="$HOMEDIR/.local/share/fonts"
_fonts_src="$HOMEDIR/Proton/Library/Fonts"
if [[ -d "$_fonts_src" ]]; then
    run_as_user mkdir -p "$_fonts_dst"
    run_as_user cp -r "$_fonts_src/." "$_fonts_dst/" 2>/dev/null || true
    run_as_user fc-cache -f >/dev/null 2>&1 || true
fi
