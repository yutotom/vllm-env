#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT_DIR"

PYTHON_VERSION="${PYTHON_VERSION:-3.12}"
TORCH_BACKEND="${TORCH_BACKEND:-auto}"
VLLM_SPEC="${VLLM_SPEC:-vllm}"
# NVIDIA GPU にアクセスできない場合は、インストール前に停止する。
if ! GPU_INFO="$(nvidia-smi \
  --query-gpu=index,name,driver_version,memory.total \
  --format=csv,noheader 2>&1)"; then
  echo "NVIDIA GPU detection failed:" >&2
  echo "$GPU_INFO" >&2
  exit 1
fi

echo "Detected NVIDIA GPU:"
echo "$GPU_INFO"
echo "Installing $VLLM_SPEC (Python $PYTHON_VERSION, torch backend: $TORCH_BACKEND)"

uv venv --python "$PYTHON_VERSION" .venv
uv pip install --python .venv/bin/python "$VLLM_SPEC" --torch-backend="$TORCH_BACKEND"

# uv がこのマシンで利用可能な CUDA build を選んだことを確認する。
.venv/bin/python - <<'PY'
import torch

print(f"torch={torch.__version__}, CUDA={torch.version.cuda}")
if not torch.cuda.is_available():
    raise SystemExit("PyTorch cannot access the NVIDIA GPU.")
print(f"GPU count={torch.cuda.device_count()}")
PY

echo "Environment is ready."

# 環境構築が成功したら、任意のディレクトリから呼べるコマンドを登録する。
BIN_DIR="${BIN_DIR:-$HOME/.local/bin}"
if mkdir -p "$BIN_DIR" &&
  chmod +x "$ROOT_DIR/vllm.sh" &&
  ln -sfn --backup=numbered "$ROOT_DIR/vllm.sh" "$BIN_DIR/vllm"; then
  echo "Installed: $BIN_DIR/vllm -> $ROOT_DIR/vllm.sh"
else
  # 自動セットアップでは、コマンド登録だけの失敗でサーバー起動を妨げない。
  if [ "${VLLM_AUTO_SETUP:-0}" = "1" ]; then
    echo "Warning: Could not register $BIN_DIR/vllm; continuing with the prepared environment." >&2
    exit 0
  fi
  echo "Could not register $BIN_DIR/vllm. The environment is ready; check BIN_DIR permissions." >&2
  exit 1
fi

case ":$PATH:" in
  *":$BIN_DIR:"*)
    ;;
  *)
    echo "Add this to your shell config if vllm is not found:"
    echo "  export PATH=\"$BIN_DIR:\$PATH\""
    ;;
esac
