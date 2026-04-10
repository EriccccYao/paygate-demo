# PayGate Demo（日本語）

言語: [English](./README.md) | [简体中文](./README.zh-CN.md) | [日本語](./README.ja.md)

公式サイト: **https://paygate.deltab.ai**

このリポジトリは、PayGate の課金フローをローカルで再現するための公式デモです。

## SDK 導入方法（本番）

公開済み npm パッケージ:

```bash
npm i @deltablab/express @deltablab/client-fetch ethers
# または
pnpm add @deltablab/express @deltablab/client-fetch ethers
```

導入モデル:

1. サーバー側で `@deltablab/express`（または `@deltablab/hono` / `@deltablab/next`）を使って有料ルートを保護
2. クライアント側で `@deltablab/client-fetch` を使って有料 API を呼び出し
3. 実行時フローは `402 challenge -> 署名 -> 再試行 -> 200`

## デモの目的

以下のフルフローを再現します:

1. クライアントが有料エンドポイントを呼ぶ
2. サーバーが `402` challenge を返す
3. クライアントが支払い証明に署名する
4. クライアントが再試行する
5. サーバーが `200` を返す

デモ対象エンドポイント:

- `GET /v1/weather`
- `POST /v1/echo`

## 前提条件

- macOS または Linux
- Node.js 20+
- `pnpm`
- `curl`
- `jq`
- `lsof`
- ローカルに PayGate ソースツリーがあり、次のディレクトリを含むこと:
  - `cloud/api`
  - `sdk/paygate-node`

## 初回セットアップ

`paygate` 側で依存関係をインストール:

```bash
cd ../paygate

cd cloud/api
pnpm install

cd ../../sdk/paygate-node
pnpm install
```

## クイックスタート

`paygate-demo` ルートで実行:

```bash
# paygate が ../paygate 以外にある場合
export PAYGATE_REPO_DIR="/absolute/path/to/paygate"

./run-node-demo.sh up
./run-node-demo.sh smoke
```

停止:

```bash
./run-node-demo.sh down
```

## コマンド一覧

| コマンド | 説明 |
|---|---|
| `./run-node-demo.sh up` | Cloud API 起動 + publisher/endpoint 登録 + publisher デモサーバー起動 |
| `./run-node-demo.sh smoke` | クライアントデモを実行し、課金フローを検証 |
| `./run-node-demo.sh status` | pid、ポート、ヘルス状態を表示 |
| `./run-node-demo.sh logs` | Cloud/register/publisher/client ログを表示 |
| `./run-node-demo.sh down` | デモプロセス停止、ポート解放 |

## 実行トポロジー

`up` で起動されるもの:

- PayGate Cloud API (`cloud/api`) on `127.0.0.1:3001`
- publisher demo server (`sdk/paygate-node/examples/publisher/server-express.ts`) on `127.0.0.1:8080`
- `example:publisher-register` により publisher / API key / endpoint ID を発行

`smoke` で実行されるもの:

- `sdk/paygate-node/examples/client/pay-per-call.ts`
- デフォルトは no-RPC モード（server-prepared tx パス）

## 実行時ファイル

`./.runtime/node-demo/` に生成:

- `env.sh`：今回実行時の環境変数
- `publisher-exports.sh`：register ステップから抽出した export
- `logs/`：`cloud.log`, `register.log`, `publisher.log`, `client.log`
- `pids/`：`cloud.pid`, `publisher.pid`

確認例:

```bash
cat .runtime/node-demo/env.sh
```

## 自分のアプリに接続する時

`up` 実行後はローカル Cloud/API key/endpoint ID が揃っているため、以下を使って自分のアプリ接続を進められます:

1. `.runtime/node-demo/env.sh` から値を取得
2. `PAYGATE_BASE_URL`, `PAYGATE_API_KEY`, `PAYGATE_PUBLISHER_ID`, endpoint ID を利用
3. 自分のサービスで challenge/verify 呼び出しを実装

フレームワーク別の実装例はメインリポジトリを参照:

- `paygate/sdk/paygate-node/examples/`
- `paygate/sdk/paygate-node/README.md`

## トラブルシューティング

### `PAYGATE_REPO_DIR is invalid`

指定先に以下が存在するか確認:

- `cloud/api`
- `sdk/paygate-node`

必要なら再設定:

```bash
export PAYGATE_REPO_DIR="/absolute/path/to/paygate"
```

### 必要コマンド不足（`pnpm`, `jq` など）

不足コマンドをインストールして再実行してください。

### ポート競合（`3001` / `8080`）

```bash
./run-node-demo.sh down
./run-node-demo.sh up
```

### register 失敗 / exports 未生成

```bash
cat .runtime/node-demo/logs/register.log
```

### macOS で `launchctl` が使われる

macOS ではスクリプトが `launchctl` を自動利用する場合があります。`status/down` はこのスクリプト経由で実行してください。

## 本番利用に関する注意

このリポジトリはローカルデモ/接続検証用です。demo 用キー、mock settlement、単一プロセス前提を本番構成にそのまま流用しないでください。
