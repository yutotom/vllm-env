#!/usr/bin/env bash
set -euo pipefail

# シンボリックリンク経由でも、このリポジトリの環境を使う。
ROOT_DIR="$(dirname "$(realpath "${BASH_SOURCE[0]}")")"

if [ ! -x "$ROOT_DIR/.venv/bin/vllm" ]; then
  echo "vLLM is not installed. Detecting this machine and setting it up..."
  VLLM_AUTO_SETUP=1 "$ROOT_DIR/setup_vllm_env.sh"
fi

# 呼び出し元の作業ディレクトリと引数を保持し、CUDA 用の依存関係は再同期しない。
UV_PROJECT_ENVIRONMENT="$ROOT_DIR/.venv" exec uv run --project "$ROOT_DIR" --no-sync \
  "$ROOT_DIR/.venv/bin/vllm" "$@"
