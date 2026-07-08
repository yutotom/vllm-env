#!/usr/bin/env bash
set -euo pipefail

BIN_DIR="${BIN_DIR:-$HOME/.local/bin}"

mkdir -p "$BIN_DIR"
chmod +x vserve.sh
ln -sfn "$(pwd)/vserve.sh" "$BIN_DIR/vserve"

echo "Installed: $BIN_DIR/vserve -> $(pwd)/vserve.sh"

case ":$PATH:" in
  *":$BIN_DIR:"*)
    ;;
  *)
    echo "Add this to your shell config if vserve is not found:"
    echo "  export PATH=\"$BIN_DIR:\$PATH\""
    ;;
esac
