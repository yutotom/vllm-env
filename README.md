# vserve

`vserve` は、vLLM の OpenAI 互換サーバーを手早く起動するための小さなラッパースクリプトです。

デフォルトでは `Qwen/Qwen3.5-9B` を `0.0.0.0:8000` で起動します。モデル名やポートなどは、引数または環境変数で変更できます。

## 必要なもの

- Linux 環境
- NVIDIA GPU と対応するドライバ
- `uv`
- Python 3.10 以上

## セットアップ

```bash
./setup_env.sh
```

このコマンドは、プロジェクト直下に `.venv` を作成し、`vllm` をインストールします。
デフォルトでは PyTorch backend は `cu128`、vLLM は Qwen3.5 対応のため `vllm>=0.23,<0.24` を指定します。

Python バージョンを指定する場合は、`PYTHON_VERSION` を使います。

```bash
PYTHON_VERSION=3.12 ./setup_env.sh
```

デフォルトの Python バージョンは `3.12` です。

PyTorch の CUDA backend を変更する場合は、`TORCH_BACKEND` を指定します。

```bash
TORCH_BACKEND=cu129 ./setup_env.sh
TORCH_BACKEND=auto ./setup_env.sh
```

vLLM のバージョン制約を変更する場合は、`VLLM_SPEC` を指定します。

```bash
VLLM_SPEC=vllm ./setup_env.sh
VLLM_SPEC='vllm>=0.23,<0.24' ./setup_env.sh
```

## 起動

```bash
./vserve.sh
```

デフォルトでは `--language-model-only` を自動で付けます。
マルチモーダルモデルとして起動したい場合は、`--MULTIMODAL` を指定してください。
`--MULTIMODAL` はこのスクリプト内で消費され、`vllm serve` には渡しません。

別のモデルを使う場合は、最初の位置引数にモデル名を指定します。

```bash
./vserve.sh Qwen/Qwen3.5-35B-A3B-FP8
```

`vllm serve` に追加オプションを渡すこともできます。最初の引数が `-` で始まらない場合だけモデル名として扱い、それ以降の引数はそのまま `vllm serve` に渡します。

```bash
./vserve.sh Qwen/Qwen3.5-9B --max-model-len 4096
```

```bash
./vserve.sh Qwen/Qwen3.5-VL-7B-Instruct --MULTIMODAL
```

モデル名を変えずに vLLM オプションだけを渡す場合は、先頭からオプションを指定します。

```bash
./vserve.sh --dtype auto
```

## LoRA を使う

Transformers/PEFT で訓練した LoRA adapter は、adapter ディレクトリをモデル引数として渡せます。
`adapter_config.json` の `base_model_name_or_path` を base model として使い、adapter 名はディレクトリ名から自動設定します。

```bash
./vserve.sh /path/to/lora
```

この場合、内部的には base model を `vllm serve` のモデルとして使い、`--enable-lora --lora-modules <adapter_dir_name>=/path/to/lora` を自動で付けます。

base model を明示したい場合や、adapter 名を指定したい場合は、`LORA_MODULES` に vLLM の `--lora-modules` へ渡す値を指定します。

```bash
LORA_MODULES="adapter_name=/path/to/lora" ./vserve.sh Qwen/Qwen3.5-9B
```

複数の LoRA adapter を登録する場合は、スペース区切りで指定します。

```bash
LORA_MODULES="adapter_a=/path/to/lora-a adapter_b=/path/to/lora-b" ./vserve.sh Qwen/Qwen3.5-9B
```

`--max-loras` は読み取れた adapter 数から、`--max-lora-rank` は各 adapter の `adapter_config.json` にある `r` / `rank_pattern` から自動設定されます。該当する `adapter_config.json` が読めない adapter は、この自動設定の対象外です。

環境変数を使わず、vLLM の引数を直接渡すこともできます。

```bash
./vserve.sh Qwen/Qwen3.5-9B --enable-lora --lora-modules adapter_name=/path/to/lora
```

## 環境変数

| 変数 | デフォルト | 説明 |
| --- | --- | --- |
| `DEFAULT_MODEL` | `Qwen/Qwen3.5-9B` | 引数でモデル名を指定しない場合に使うモデル |
| `HOST` | `0.0.0.0` | vLLM サーバーの bind host |
| `PORT` | `8000` | vLLM サーバーの port |
| `GPU_MEMORY_UTILIZATION` | `0.90` | vLLM の `--gpu-memory-utilization` |
| `MAX_MODEL_LEN` | `4096` | vLLM の `--max-model-len` |
| `LORA_MODULES` | 未指定 | 指定した場合に `--enable-lora --lora-modules` として渡す LoRA adapter。adapter ディレクトリをモデル引数にした場合は自動設定 |
| `ATTENTION_BACKEND` | 未指定 | 指定した場合に vLLM の `--attention-backend` として渡す。FlashAttention で失敗する場合は `FLASHINFER` や `TRITON_ATTN` を試す |
| `SKIP_CUDA_CHECK` | `0` | `1` にすると起動前の `torch.cuda.is_available()` チェックを省略 |

例:

```bash
HOST=127.0.0.1 PORT=8080 GPU_MEMORY_UTILIZATION=0.80 MAX_MODEL_LEN=8192 ./vserve.sh
```

## `vserve` コマンドとして使う

`install_vserve.sh` を実行すると、`$HOME/.local/bin/vserve` にシンボリックリンクを作成します。

```bash
./install_vserve.sh
```

`$HOME/.local/bin` が `PATH` に入っていない場合は、シェル設定に追加してください。

```bash
export PATH="$HOME/.local/bin:$PATH"
```

インストール後は、任意のディレクトリから次のように起動できます。

```bash
vserve
vserve Qwen/Qwen3.5-9B --dtype auto
```

## API への接続例

サーバー起動後、OpenAI 互換 API として利用できます。

```bash
curl http://localhost:8000/v1/models
```

チャット補完の例:

```bash
curl http://localhost:8000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "Qwen/Qwen3.5-9B",
    "messages": [
      {"role": "user", "content": "こんにちは"}
    ]
  }'
```

## トラブルシュート

`.venv is missing. Run ./setup_env.sh first.` と表示された場合は、先にセットアップを実行してください。

```bash
./setup_env.sh
```

GPU メモリ不足で起動できない場合は、モデルを小さくするか、`GPU_MEMORY_UTILIZATION` や vLLM の追加オプションを調整してください。

`CUDA driver version is insufficient for CUDA runtime version` と表示される場合は、インストールされた PyTorch/vLLM の CUDA runtime が NVIDIA driver より新しい状態です。
まず driver と GPU が見えているか確認してください。

```bash
nvidia-smi
.venv/bin/python -c 'import torch; print(torch.__version__, torch.version.cuda, torch.cuda.is_available())'
```

Qwen3.5 を使う場合は、古い `vllm==0.10.2` へ戻さないでください。Qwen3.5 は新しいモデル構成を使うため、古い vLLM では読み込めないことがあります。

FlashAttention 関連のエラーが出る場合は、まず CUDA 12.8 backend と Qwen3.5 対応の vLLM で環境を作り直してください。

```bash
rm -rf .venv
TORCH_BACKEND=cu128 VLLM_SPEC='vllm>=0.23,<0.24' ./setup_env.sh
```

それでも FlashAttention で失敗する場合は、FlashAttention 以外の attention backend を指定して起動します。

```bash
ATTENTION_BACKEND=FLASHINFER ./vserve.sh Qwen/Qwen3.5-9B
ATTENTION_BACKEND=TRITON_ATTN ./vserve.sh Qwen/Qwen3.5-9B
```

より新しい driver を使える環境では、`TORCH_BACKEND=cu129`、`TORCH_BACKEND=auto`、`VLLM_SPEC=vllm` でも構いません。
