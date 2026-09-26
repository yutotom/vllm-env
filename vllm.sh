#!/usr/bin/env bash
set -euo pipefail

# シンボリックリンク経由でも、このリポジトリの環境を使う。
ROOT_DIR="$(dirname "$(realpath "${BASH_SOURCE[0]}")")"

# .envrc 内の相対パスはリポジトリ基準で解決し、実行元へ戻す。
CALLER_DIR="$PWD"
cd "$ROOT_DIR"
if [ -f "$ROOT_DIR/.envrc" ]; then
  source "$ROOT_DIR/.envrc"
fi
VENV_DIR="${UV_PROJECT_ENVIRONMENT:-${VIRTUAL_ENV:-$ROOT_DIR/.venv}}"
VENV_DIR="$(realpath -m "$VENV_DIR")"
export VIRTUAL_ENV="$VENV_DIR"
export UV_PROJECT_ENVIRONMENT="$VENV_DIR"
cd "$CALLER_DIR"

if [ ! -x "$VENV_DIR/bin/vllm" ]; then
  echo "vLLM is not installed. Detecting this machine and setting it up..."
  VLLM_AUTO_SETUP=1 "$ROOT_DIR/setup_vllm_env.sh"
fi

# CUDA wheel の lib/ 配置と、バージョン付き runtime のみの構成に対応する。
if [ -n "${CUDA_HOME:-}" ]; then
  for CUDA_LIB_DIR in "$CUDA_HOME/lib" "$CUDA_HOME/lib64"; do
    for CUDA_RUNTIME in "$CUDA_LIB_DIR/libcudart.so" "$CUDA_LIB_DIR"/libcudart.so.*; do
      [ -f "$CUDA_RUNTIME" ] || continue
      CUDA_LINK_DIR="$VENV_DIR/lib/vllm-cuda"
      mkdir -p "$CUDA_LINK_DIR"
      ln -sfn "$(realpath "$CUDA_RUNTIME")" "$CUDA_LINK_DIR/libcudart.so"
      export LIBRARY_PATH="$CUDA_LINK_DIR:$CUDA_LIB_DIR${LIBRARY_PATH:+:$LIBRARY_PATH}"
      export LD_LIBRARY_PATH="$CUDA_LIB_DIR${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
      break 2
    done
  done
fi

# 呼び出し元の作業ディレクトリと引数を保持し、CUDA 用の依存関係は再同期しない。
exec uv run --project "$ROOT_DIR" --no-sync "$VENV_DIR/bin/vllm" "$@"
