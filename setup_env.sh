#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT_DIR"

PYTHON_VERSION="${PYTHON_VERSION:-3.12}"
TORCH_BACKEND="${TORCH_BACKEND:-auto}"
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
echo "Installing vllm (Python $PYTHON_VERSION, torch backend: $TORCH_BACKEND)"

uv venv --python "$PYTHON_VERSION" .venv
uv pip install --python .venv/bin/python vllm --torch-backend="$TORCH_BACKEND"

# uv がこのマシンで利用可能な CUDA build を選んだことを確認する。
.venv/bin/python - <<'PY'
import torch

print(f"torch={torch.__version__}, CUDA={torch.version.cuda}")
if not torch.cuda.is_available():
    raise SystemExit("PyTorch cannot access the NVIDIA GPU.")
print(f"GPU count={torch.cuda.device_count()}")
PY

echo "Environment is ready."
