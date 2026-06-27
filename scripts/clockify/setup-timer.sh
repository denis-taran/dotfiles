#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UNIT_DIR="$HOME/.config/systemd/user"

mkdir -p "$UNIT_DIR"

cp "$SCRIPT_DIR/clockify-backup.service" "$UNIT_DIR/"
cp "$SCRIPT_DIR/clockify-backup.timer" "$UNIT_DIR/"

systemctl --user daemon-reload
systemctl --user enable --now clockify-backup.timer

echo "Systemd timer installed and started."
