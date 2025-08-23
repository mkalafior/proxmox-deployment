#!/bin/bash
set -euo pipefail

TARGET_DIR="${1:-$HOME/.proxmox-deploy/templates}"
BIN_DIR="${2:-$HOME/.local/bin}"

mkdir -p "$TARGET_DIR" "$BIN_DIR"

if [[ ! -d "$TARGET_DIR/.git" ]]; then
  git clone --depth 1 "$(cd "$(dirname "$0")/.." && pwd)" "$TARGET_DIR"
else
  echo "Templates already installed at $TARGET_DIR"
  git -C "$TARGET_DIR" pull
fi

SRC_CLI="$(cd "$(dirname "$0")" && pwd)/proxmox-deploy"
DEST_CLI="$BIN_DIR/pxdcli"
chmod +x "$SRC_CLI"
ln -sf "$SRC_CLI" "$DEST_CLI"
echo "Installed pxdcli to $DEST_CLI"
echo "Add $BIN_DIR to your PATH if not present."


