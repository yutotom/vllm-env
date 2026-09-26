#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(dirname "$(realpath "${BASH_SOURCE[0]}")")"
cd "$ROOT_DIR"

# direnv が有効でないシェルでも、リポジトリの設定を読み込む。
if [ -f "$ROOT_DIR/.envrc" ]; then
  source "$ROOT_DIR/.envrc"
fi
VENV_DIR="${UV_PROJECT_ENVIRONMENT:-${VIRTUAL_ENV:-$ROOT_DIR/.venv}}"
VENV_DIR="$(realpath -m "$VENV_DIR")"
export VIRTUAL_ENV="$VENV_DIR"
export UV_PROJECT_ENVIRONMENT="$VENV_DIR"

PYTHON_VERSION="${PYTHON_VERSION:-3.12}"
# CUDA compiler と PyTorch の runtime/header を 13.0 系に統一する。
TORCH_BACKEND="${TORCH_BACKEND:-cu130}"
if [ "$TORCH_BACKEND" != "cu130" ]; then
  echo "This setup requires TORCH_BACKEND=cu130 (CUDA 13.0)." >&2
  exit 1
fi
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

# 再実行時も既存環境を保持し、CUDA パッケージを修復できるようにする。
if [ ! -x "$VENV_DIR/bin/python" ]; then
  uv venv --python "$PYTHON_VERSION" "$VENV_DIR"
fi
uv pip install --python "$VENV_DIR/bin/python" "$VLLM_SPEC" \
  --torch-backend="$TORCH_BACKEND" \
  'nvidia-cuda-nvcc==13.0.88' \
  'nvidia-cuda-crt==13.0.88' \
  'nvidia-nvvm==13.0.88' \
  'nvidia-cuda-cccl==13.0.85' \
  'nvidia-cuda-runtime>=13.0,<13.1' \
  'nvidia-cuda-nvrtc>=13.0,<13.1' \
  'nvidia-cuda-cupti>=13.0,<13.1'

# CUDA 13.0 build と GPU へのアクセスを確認する。
"$VENV_DIR/bin/python" - <<'PY'
import torch

print(f"torch={torch.__version__}, CUDA={torch.version.cuda}")
if torch.version.cuda != "13.0":
    raise SystemExit("Expected PyTorch built for CUDA 13.0; check the installed torch/vLLM versions.")
if not torch.cuda.is_available():
    raise SystemExit("PyTorch cannot access the NVIDIA GPU.")
print(f"GPU count={torch.cuda.device_count()}")
PY

echo "Environment is ready: $VENV_DIR"

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
