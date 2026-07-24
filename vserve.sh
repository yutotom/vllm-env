#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$(realpath "$0")")"

MODEL="${DEFAULT_MODEL:-Qwen/Qwen3.5-9B}"
HOST="${HOST:-0.0.0.0}"
PORT="${PORT:-8000}"
GPU_MEMORY_UTILIZATION="${GPU_MEMORY_UTILIZATION:-0.90}"
MAX_MODEL_LEN="${MAX_MODEL_LEN:-2048}"
LORA_MODULES="${LORA_MODULES:-}"
ATTENTION_BACKEND="${ATTENTION_BACKEND:-FLASH_ATTN}"

PYTHON_BIN=".venv/bin/python"

if [ ! -x .venv/bin/vllm ]; then
  echo "vLLM is not installed. Detecting this machine and setting it up..."
  ./setup_env.sh
fi

# FlashInfer の JIT build が壊れた CUDA_HOME を参照しないように補正する。
CUDA_TOOLKIT_ROOT="${CUDA_HOME:-${CUDA_PATH:-}}"
while [[ "$CUDA_TOOLKIT_ROOT" == *: ]]; do
  CUDA_TOOLKIT_ROOT="${CUDA_TOOLKIT_ROOT%:}"
done

if [ ! -x "${CUDA_TOOLKIT_ROOT:+$CUDA_TOOLKIT_ROOT/bin/nvcc}" ]; then
  if NVCC_BIN="$(command -v nvcc 2>/dev/null)"; then
    CUDA_TOOLKIT_ROOT="$(dirname "$(dirname "$(realpath "$NVCC_BIN")")")"
  else
    CUDA_TOOLKIT_ROOT=""
  fi
fi

if [ -n "$CUDA_TOOLKIT_ROOT" ]; then
  export CUDA_HOME="$CUDA_TOOLKIT_ROOT"
  export CUDA_PATH="$CUDA_TOOLKIT_ROOT"
fi

SITE_PACKAGES="$("$PYTHON_BIN" -c 'import sysconfig; print(sysconfig.get_paths()["purelib"])')"
NVIDIA_LIBRARY_PATHS="$("$PYTHON_BIN" - "$SITE_PACKAGES" <<'PY'
import pathlib
import sys

site_packages = pathlib.Path(sys.argv[1])
paths = [site_packages / "torch" / "lib"]
paths.extend(sorted((site_packages / "nvidia").glob("*/lib")))
print(":".join(str(path) for path in paths if path.is_dir()))
PY
)"
export LD_LIBRARY_PATH="$NVIDIA_LIBRARY_PATHS${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

if [ "${SKIP_CUDA_CHECK:-0}" != "1" ] && [ "${1:-}" != "--help" ] && [ "${1:-}" != "-h" ]; then
  CUDA_CHECK_OUTPUT="$("$PYTHON_BIN" <<'PY' 2>&1
import torch

print(f"torch={torch.__version__}")
print(f"torch_cuda={torch.version.cuda}")
print(f"cuda_available={torch.cuda.is_available()}")
if not torch.cuda.is_available():
    raise SystemExit(1)
PY
)" || {
    echo "CUDA is not available to torch; vLLM cannot start." >&2
    echo "$CUDA_CHECK_OUTPUT" >&2
    if command -v nvidia-smi >/dev/null 2>&1; then
      nvidia-smi >&2 || true
    else
      echo "nvidia-smi was not found." >&2
    fi
    echo "Check that the NVIDIA driver is running, /dev/nvidia* is visible, and the installed torch CUDA backend matches the driver." >&2
    echo "To bypass this preflight check, set SKIP_CUDA_CHECK=1." >&2
    exit 1
  }
fi

MULTIMODAL=0
FILTERED_ARGS=()
for arg in "$@"; do
  case "$arg" in
    --MULTIMODAL)
      MULTIMODAL=1
      ;;
    *)
      FILTERED_ARGS+=("$arg")
      ;;
  esac
done
set -- "${FILTERED_ARGS[@]}"

ARGS=()
if [ "$#" -gt 0 ] && [[ "$1" != -* ]]; then
  MODEL="$1"
  shift
fi

ARGS=("$@")

infer_lora_base_model() {
  "$PYTHON_BIN" - "$1" <<'PY'
import json
import pathlib
import sys

adapter_config = pathlib.Path(sys.argv[1]) / "adapter_config.json"
try:
    data = json.loads(adapter_config.read_text())
except Exception:
    sys.exit(1)

base_model = data.get("base_model_name_or_path")
if not base_model:
    sys.exit(1)

print(base_model)
PY
}

infer_lora_limits() {
  "$PYTHON_BIN" - "$@" <<'PY'
import json
import pathlib
import sys

max_rank = 0
count = 0

for spec in sys.argv[1:]:
    path = spec.split("=", 1)[1] if "=" in spec else spec
    adapter_config = pathlib.Path(path).expanduser() / "adapter_config.json"
    if not adapter_config.is_file():
        continue

    try:
        data = json.loads(adapter_config.read_text())
    except Exception:
        continue

    count += 1
    ranks = []
    if isinstance(data.get("r"), int):
        ranks.append(data["r"])

    rank_pattern = data.get("rank_pattern")
    if isinstance(rank_pattern, dict):
        ranks.extend(value for value in rank_pattern.values() if isinstance(value, int))

    if ranks:
        max_rank = max(max_rank, *ranks)

print(f"{count} {max_rank}")
PY
}

if [ -z "$LORA_MODULES" ] && [ -f "$MODEL/adapter_config.json" ]; then
  ADAPTER_PATH="$MODEL"
  if ! BASE_MODEL="$(infer_lora_base_model "$ADAPTER_PATH")"; then
    echo "LoRA adapter was passed as MODEL, but base_model_name_or_path could not be read from adapter_config.json." >&2
    echo "Pass the base model as the first argument and set LORA_MODULES manually." >&2
    exit 1
  fi
  ADAPTER_NAME="$(basename "$ADAPTER_PATH")"
  LORA_MODULES="${ADAPTER_NAME:-lora_adapter}=$ADAPTER_PATH"
  MODEL="$BASE_MODEL"
fi

OPTS=(
  --host "$HOST"
  --port "$PORT"
  --gpu-memory-utilization "$GPU_MEMORY_UTILIZATION"
  --max-model-len "$MAX_MODEL_LEN"
  # 起動時の互換性を優先し、eager execution を常に既定値として使う。
  --enforce-eager
)

if [ "$MULTIMODAL" != "1" ]; then
  OPTS+=(--language-model-only)
fi

if [ -n "$ATTENTION_BACKEND" ]; then
  OPTS+=(--attention-backend "$ATTENTION_BACKEND")
fi

if [ -n "$LORA_MODULES" ]; then
  read -r -a LORA_MODULE_ARGS <<< "$LORA_MODULES"
  OPTS+=(--enable-lora --lora-modules "${LORA_MODULE_ARGS[@]}")

  read -r INFERRED_MAX_LORAS INFERRED_MAX_LORA_RANK < <(infer_lora_limits "${LORA_MODULE_ARGS[@]}")
  if [ "${INFERRED_MAX_LORAS:-0}" -gt 0 ]; then
    OPTS+=(--max-loras "$INFERRED_MAX_LORAS")
  fi
  if [ "${INFERRED_MAX_LORA_RANK:-0}" -gt 0 ]; then
    OPTS+=(--max-lora-rank "$INFERRED_MAX_LORA_RANK")
  fi
fi

exec .venv/bin/vllm serve "$MODEL" "${OPTS[@]}" "${ARGS[@]}"
