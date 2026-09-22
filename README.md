# vserve

このプロジェクトは、vLLM の環境構築と標準 CLI の実行を簡単にするスクリプトです。

`setup_vllm_env.sh` で環境を構築し、`vllm.sh` または登録済みの `vllm` コマンドから実行します。

## 必要なもの

- Linux 環境
- NVIDIA GPU と対応するドライバ
- `uv`
- Python 3.10 以上

## セットアップ

セットアップを個別に行う必要はありません。初回起動時に NVIDIA GPU と driver を確認し、マシンに合う PyTorch CUDA backend を `uv` で自動選択して、`.venv` に vLLM をインストールします。

```bash
./vllm.sh serve Qwen/Qwen3.5-9B
```

環境構築と `vllm` コマンドの登録を先に行う場合は、次を実行します。

```bash
./setup_vllm_env.sh
```

このコマンドは GPU 構成を表示し、プロジェクト直下に `.venv` を作成します。vLLM はデフォルトで、インストール時点の最新版を使用します。環境構築が成功すると、`$HOME/.local/bin/vllm` に `vllm.sh` へのシンボリックリンクを作成します。既存の同名コマンドは番号付きバックアップに退避します。初回起動時の自動セットアップでも同じ処理を行います。

初回起動時は、書き込み権限などの理由でコマンド登録に失敗しても、警告を表示してサーバー起動へ進みます。`./setup_vllm_env.sh` を直接実行した場合は、登録失敗をエラーとして終了します。どちらの場合も、環境構築自体の失敗では処理を停止します。

Python バージョンを指定する場合は、`PYTHON_VERSION` を使います。

```bash
PYTHON_VERSION=3.12 ./setup_vllm_env.sh
```

デフォルトの Python バージョンは `3.12` です。

通常、PyTorch backend の指定は不要です。自動検出を上書きする場合だけ `TORCH_BACKEND` を指定します。

```bash
TORCH_BACKEND=cu129 ./setup_vllm_env.sh
TORCH_BACKEND=cu128 ./setup_vllm_env.sh
```

vLLM のバージョン制約を変更する場合は、`VLLM_SPEC` を指定します。

```bash
VLLM_SPEC='vllm==0.24.0' ./setup_vllm_env.sh
VLLM_SPEC='vllm>=0.24,<0.25' ./setup_vllm_env.sh
```

## 起動

サブコマンドを含む全引数を vLLM CLI にそのまま渡します。

```bash
./vllm.sh --help
./vllm.sh serve Qwen/Qwen3.5-9B --host 127.0.0.1 --port 8000
./vllm.sh serve Qwen/Qwen3.5-9B --max-model-len 4096 --gpu-memory-utilization 0.90
```

独自の既定値は追加しません。オプションは `./vllm.sh serve --help` で確認できます。

## LoRA とマルチモーダル

LoRA はベースモデルと adapter を明示します。必要に応じて `--max-loras` と `--max-lora-rank` も指定してください。adapter 設定からの自動推定は行いません。

```bash
./vllm.sh serve Qwen/Qwen3.5-9B --enable-lora --lora-modules adapter_name=/path/to/lora
```

マルチモーダルモデルも標準の `serve` で起動します。独自の `--MULTIMODAL` は不要です。言語モデルのみで使う場合は `--language-model-only` を指定します。

## 旧スクリプトからの移行

旧サーバー起動ラッパーは削除しました。`HOST`、`PORT`、`MAX_MODEL_LEN` などの独自環境変数は `--host`、`--port`、`--max-model-len` などの CLI 引数に置き換えてください。CUDA パス補正や LoRA の自動設定も行いません。

## 任意のディレクトリから `vllm` を使う

`setup_vllm_env.sh` は環境構築とコマンド登録をまとめて行います。以前の `vserve` 登録から切り替える場合も、次の手順で `vllm` を登録できます。

```bash
./setup_vllm_env.sh
```

登録先は環境変数 `BIN_DIR` で変更できます。既定の `$HOME/.local/bin` が `PATH` に入っていない場合は、シェル設定に追加してください。

```bash
export PATH="$HOME/.local/bin:$PATH"
```

インストール後は、任意のディレクトリから次のように起動できます。

```bash
vllm --help
vllm serve Qwen/Qwen3.5-9B --dtype auto
vllm serve ./my-model --port 8080
```

`vllm` は、このリポジトリの `.venv` を使う `uv run --no-sync` 経由で vLLM CLI を実行します。サブコマンドを含む全引数をそのまま渡し、相対パスは呼び出し元のディレクトリを基準に解決します。依存関係の再同期は行わず、セットアップで選択した CUDA backend を維持します。

環境構築済みでコマンド登録だけを変更する場合は、リポジトリ内で次を実行できます。

```bash
chmod +x vllm.sh
mkdir -p "$HOME/.local/bin"
ln -sfn --backup=numbered "$PWD/vllm.sh" "$HOME/.local/bin/vllm"
hash -r
```

## 既存の skill について

`.agents/skills/use-vserve` は旧 `vserve` コマンドを前提とした内容です。現在の起動経路には未対応のため、上記の `vllm` コマンドを直接使用してください。

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

初回起動時の自動セットアップに失敗した場合は、表示された GPU 検出またはインストールのエラーを確認してください。`nvidia-smi` が成功しない環境ではセットアップできません。

GPU メモリ不足で起動できない場合は、モデルを小さくするか、`--gpu-memory-utilization` や `--max-model-len`を調整してください。

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
TORCH_BACKEND=cu128 ./setup_vllm_env.sh
```

FlashInfer の JIT build で `nvcc: not found` と表示される場合は、CUDA toolkit の `nvcc` が `PATH` 上にあるか確認してください。`CUDA_HOME` は正しい CUDA toolkit のパスに設定してください。

それでも FlashAttention で失敗する場合は、FlashAttention 以外の attention backend を指定して起動します。

```bash
./vllm.sh serve Qwen/Qwen3.5-9B --attention-backend FLASHINFER
./vllm.sh serve Qwen/Qwen3.5-9B --attention-backend TRITON_ATTN
```

より新しい driver を使える環境では、`TORCH_BACKEND=cu129` または `TORCH_BACKEND=auto` も利用できます。
