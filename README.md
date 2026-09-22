# vserve

このプロジェクトは、vLLM の環境構築と標準 CLI の実行を簡単にするスクリプトです。

NVIDIA GPU とドライバを確認し、マシンに合う PyTorch CUDA backend を `uv` で自動選択します。

## 必要なもの

- Linux 環境
- NVIDIA GPU と対応するドライバ（`nvidia-smi` が実行できること）
- `uv`
- Python 3.10 以上（セットアップの既定値は `3.12`）

## クイックスタート

リポジトリ内で次を実行します。初回は自動で `.venv` に vLLM をインストールするため、事前のセットアップは不要です。

```bash
./vllm.sh serve Qwen/Qwen3.5-9B --host 127.0.0.1 --port 8000
```

### API への接続

サーバー起動後、別のターミナルから OpenAI 互換 API に接続できます。

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

## 起動オプション

サブコマンドを含む全引数を vLLM CLI にそのまま渡します。

```bash
./vllm.sh --help
./vllm.sh serve Qwen/Qwen3.5-9B --max-model-len 4096 --gpu-memory-utilization 0.90
```

独自の既定値は追加しません。オプションは `./vllm.sh serve --help` で確認できます。

### LoRA とマルチモーダル

LoRA はベースモデルとアダプターを明示します。必要に応じて `--max-loras` と `--max-lora-rank` も指定してください。アダプター設定からの自動推定は行いません。

```bash
./vllm.sh serve Qwen/Qwen3.5-9B --enable-lora --lora-modules adapter_name=/path/to/lora
```

マルチモーダルモデルも標準の `serve` で起動します。言語モデルのみで使う場合は `--language-model-only` を指定します。

## セットアップの設定

環境構築とコマンド登録を先に行う場合は、次を実行します。

```bash
./setup_vllm_env.sh
```

GPU 構成を表示し、プロジェクト直下の `.venv` に vLLM をインストールします。次の環境変数で設定を変更できます。初回起動時の自動セットアップにも適用されます。

| 環境変数 | 既定値 | 用途 |
| --- | --- | --- |
| `PYTHON_VERSION` | `3.12` | セットアップに使う Python バージョン |
| `TORCH_BACKEND` | `auto` | PyTorch backend。通常は自動検出を使用 |
| `VLLM_SPEC` | `vllm` | vLLM のパッケージ指定。既定ではインストール時点の最新版 |
| `BIN_DIR` | `$HOME/.local/bin` | `vllm` コマンドの登録先 |

```bash
# Python バージョンを指定する。
PYTHON_VERSION=3.12 ./setup_vllm_env.sh

# backend の自動検出を上書きする場合の例。
TORCH_BACKEND=cu128 ./setup_vllm_env.sh
TORCH_BACKEND=cu129 ./setup_vllm_env.sh

# vLLM のバージョンを固定、または範囲指定する場合の例。
VLLM_SPEC='vllm==0.24.0' ./setup_vllm_env.sh
VLLM_SPEC='vllm>=0.24,<0.25' ./setup_vllm_env.sh
```

### 任意のディレクトリから `vllm` を使う

環境構築が成功すると、登録先に `vllm.sh` へのシンボリックリンクを作成します。既定の登録先は `$HOME/.local/bin/vllm` です。既存の同名コマンドは番号付きバックアップに退避します。初回起動時の自動セットアップでも同じ処理を行います。

既定の `$HOME/.local/bin` が `PATH` に入っていない場合は、シェル設定に追加してください。

```bash
export PATH="$HOME/.local/bin:$PATH"
```

インストール後は、任意のディレクトリから次のように起動できます。

```bash
vllm --help
vllm serve Qwen/Qwen3.5-9B --dtype auto
vllm serve ./my-model --port 8080
```

`vllm` は、このリポジトリの `.venv` を使う `uv run --no-sync` 経由で vLLM CLI を実行します。相対パスは呼び出し元のディレクトリを基準に解決します。依存関係の再同期は行わず、セットアップで選択した CUDA backend を維持します。

環境構築済みでコマンド登録だけを変更する場合は、リポジトリ内で次を実行できます。

```bash
chmod +x vllm.sh
mkdir -p "$HOME/.local/bin"
ln -sfn --backup=numbered "$PWD/vllm.sh" "$HOME/.local/bin/vllm"
hash -r
```

### コマンド登録に失敗した場合

書き込み権限などの理由でコマンド登録に失敗した場合の動作は、起動方法によって異なります。

- `./vllm.sh` からの自動セットアップ：警告を表示し、構築済みの環境で vLLM の実行へ進みます。
- `./setup_vllm_env.sh` の直接実行：登録失敗をエラーとして終了します。`BIN_DIR` の権限を確認してください。

どちらの場合も、環境構築自体の失敗では処理を停止します。

## トラブルシュート

### セットアップに失敗する

初回起動時の自動セットアップに失敗した場合は、表示された GPU 検出またはインストールのエラーを確認してください。`nvidia-smi` が成功しない環境ではセットアップできません。

### GPU メモリが不足する

GPU メモリ不足で起動できない場合は、モデルを小さくするか、`--gpu-memory-utilization` や `--max-model-len` を調整してください。

### CUDA ドライバとランタイムが一致しない

`CUDA driver version is insufficient for CUDA runtime version` と表示される場合は、インストールされた PyTorch/vLLM の CUDA runtime が NVIDIA ドライバより新しい状態です。
まずドライバと GPU が見えているか確認してください。

```bash
nvidia-smi
.venv/bin/python -c 'import torch; print(torch.__version__, torch.version.cuda, torch.cuda.is_available())'
```

### Qwen3.5・FlashAttention 関連のエラー

Qwen3.5 を使う場合は、古い `vllm==0.10.2` へ戻さないでください。Qwen3.5 は新しいモデル構成を使うため、古い vLLM では読み込めないことがあります。

FlashAttention 関連のエラーが出る場合は、まず CUDA 12.8 backend と Qwen3.5 対応の vLLM で環境を作り直してください。

```bash
rm -rf .venv
TORCH_BACKEND=cu128 ./setup_vllm_env.sh
```

FlashInfer の JIT build で `nvcc: not found` と表示される場合は、CUDA toolkit の `nvcc` が `PATH` 上にあるか確認してください。`CUDA_HOME` は正しい CUDA toolkit のパスに設定してください。

それでも FlashAttention で失敗する場合は、FlashAttention 以外の attention backend を指定して起動します。

```bash
./vllm.sh serve Qwen/Qwen3.5-9B --attention-backend FLASHINFER
./vllm.sh serve Qwen/Qwen3.5-9B --attention-backend TRITON_ATTN
```

より新しいドライバを使える環境では、`TORCH_BACKEND=cu129` または `TORCH_BACKEND=auto` も利用できます。

## 旧スクリプトからの移行

旧サーバー起動ラッパーは削除しました。`HOST`、`PORT`、`MAX_MODEL_LEN` などの独自環境変数は `--host`、`--port`、`--max-model-len` などの CLI 引数に置き換えてください。CUDA パス補正や LoRA の自動設定も行いません。

以前の `vserve` 登録から切り替える場合は、`./setup_vllm_env.sh` で `vllm` コマンドを登録してください。マルチモーダルモデルも標準の `serve` を使うため、独自の `--MULTIMODAL` は不要です。

### 既存の skill について

`.agents/skills/use-vserve` は旧 `vserve` コマンドを前提とした内容です。現在の起動経路には未対応のため、上記の `vllm` コマンドを直接使用してください。
