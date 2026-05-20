# Dotfiles

Personal workstation dotfiles and bootstrap scripts for Linux and Windows.

## Overview

- `scripts/install-linux.sh`: Ubuntu bootstrap. Installs core packages and links dotfiles.
- `scripts/Install-Windows.ps1`: Windows bootstrap. Installs packages via winget, links profiles, and adjusts system settings.

Both environments share comparable aliases (`g`, `c`, `vi`, `k`) and use XDG base directories where practical.

## Local files

Keep secrets out of this repo. Machine-specific files assumed to exist:
- `~/.env.sh` for local overrides
- `~/.config/git/local` for identity and signing config

## Usage

After setting up WSL for the first time, the 1Password agent stores SSH keys, but the Linux SSH client still cannot reach it yet. Clone the repository with `ssh.exe` and the signing program directly:

```bash
mkdir -p ~/Code
GIT_SSH_COMMAND="ssh.exe" \
  git -c gpg.ssh.program="/mnt/c/Users/$USER/AppData/Local/Microsoft/WindowsApps/op-ssh-sign-wsl.exe" \
  clone git@github.com:denis-taran/dotfiles.git ~/Code/dotfiles
```

After that, run the install script - it configures `core.sshCommand` and the signing program automatically.

Linux:

```bash
sudo ./scripts/install-linux.sh
```

Windows:

```powershell
.\scripts\Install-Windows.ps1
```
