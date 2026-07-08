#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

PYTHON_VERSION="${PYTHON_VERSION:-3.12}"
TORCH_BACKEND="${TORCH_BACKEND:-cu128}"
VLLM_SPEC="${VLLM_SPEC:-vllm>=0.23,<0.24}"

uv venv --python "$PYTHON_VERSION" .venv
uv pip install "$VLLM_SPEC" --torch-backend="$TORCH_BACKEND"

echo "Environment is ready. torch backend: $TORCH_BACKEND, vLLM spec: $VLLM_SPEC"
