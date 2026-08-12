# Dotfiles

Personal workstation dotfiles and bootstrap scripts for Linux and Windows.

## Overview

- `scripts/install-linux.sh`: Ubuntu bootstrap. Installs core packages and links dotfiles.
- `scripts/Install-Windows.ps1`: Windows bootstrap. Installs packages via winget, links profiles, and adjusts system settings.

Both environments share comparable aliases (`g`, `c`, `vi`, `k`) and use XDG base directories where practical.

## Local files

Keep secrets out of this repo. Environment files live in the private
`~/Code/private-configuration` repository and are linked by the bootstrap:

- `env.sh` to `~/.env.sh` on Linux
- `env.ps1` to `~/env.ps1` on Windows
- `~/.config/git/local` for identity and signing config
