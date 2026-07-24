# AGENTS.md

## このリポジトリの目的

Linux / NVIDIA GPU 環境を自動検出し、vLLM の OpenAI 互換サーバーを簡単に起動するための小さなプロジェクトです。

## 言語

- 思考は英語で行い、ユーザーへの説明は日本語で行ってください。
- コード内のコメントは、周囲の記述に合わせて日本語または英語で簡潔に書いてください。

## 実装方針

- 構成を小さく保ち、依存関係の管理には `uv` を使用してください。
- 対象は Linux、NVIDIA GPU、Python 3.10 以上です。
- GPU や CUDA backend を固定せず、原則として実行マシンから検出してください。
- `vserve.sh` に渡された未知の引数は `vllm serve` へそのまま渡してください。
- LoRA と `--MULTIMODAL` の既存動作を維持してください。
- 既存の未コミット変更を保持し、依頼と無関係なファイルを変更しないでください。

## 主なファイル

- `vserve.sh`: 必要なら環境を自動構築し、vLLM サーバーを起動します。
- `setup_env.sh`: GPU を確認し、マシンに合う PyTorch backend と vLLM を `.venv` に導入します。
- `install_vserve.sh`: `vserve` コマンドのシンボリックリンクを作成します。
- `README.md`: 利用方法と設定項目を説明します。

## 確認

変更後は最低限、次を実行してください。

```bash
bash -n setup_env.sh
bash -n vserve.sh
bash -n install_vserve.sh
```

GPU とネットワークを利用できる場合は、セットアップと CLI も確認してください。

```bash
./setup_env.sh
./vserve.sh --help
```

実機確認できない場合は、完了報告にその理由を記載してください。
