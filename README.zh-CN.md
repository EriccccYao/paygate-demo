# PayGate Demo（中文）

语言切换: [English](./README.md) | [简体中文](./README.zh-CN.md) | [日本語](./README.ja.md)

这是一个独立的 PayGate 本地演示仓库，用于快速跑通 Node 发布方 + 客户端的完整付费调用流程。

核心代码仍在主仓库：

- https://github.com/tomo-inc/paygate

本仓库只负责：

- 演示脚本
- 演示说明文档
- 运行期日志与环境文件输出

## 这个仓库解决什么问题

它用于稳定复现以下链路：

1. 客户端访问受保护接口
2. 服务端返回 `402` 挑战
3. 客户端签名支付证明
4. 客户端重试请求
5. 服务端返回 `200`

默认演示接口：

- `GET /v1/weather`
- `POST /v1/echo`

## 范围边界

本仓库 **不包含** PayGate Cloud/API/SDK 实现本体；它会调你本地的 `paygate` 主仓库。

关键文件：

- 启动脚本: `./run-node-demo.sh`
- 运行产物: `./.runtime/node-demo/`

## 前置条件

- macOS 或 Linux
- Node.js 20+
- `pnpm`
- `curl`
- `jq`
- `lsof`
- 本地已拉取 `paygate` 主仓库

## 推荐目录结构

```text
<workspace>/
  paygate/        # 主仓库
  paygate-demo/   # 本仓库
```

如果你不是这个结构，需要设置 `PAYGATE_REPO_DIR`。

## 一次性准备

先在主仓库安装依赖：

```bash
cd ../paygate

cd cloud/api
pnpm install

cd ../../sdk/paygate-node
pnpm install
```

## 快速开始

在 `paygate-demo` 根目录执行：

```bash
# 如果主仓库不在 ../paygate，需要手动指定
export PAYGATE_REPO_DIR="/绝对路径/paygate"

./run-node-demo.sh up
./run-node-demo.sh smoke
```

停止：

```bash
./run-node-demo.sh down
```

## 命令说明

| 命令 | 作用 |
|---|---|
| `./run-node-demo.sh up` | 启动 Cloud API + 注册 publisher/endpoint + 启动 publisher demo 服务 |
| `./run-node-demo.sh smoke` | 运行客户端演示，验证完整支付链路 |
| `./run-node-demo.sh status` | 查看进程、端口监听、健康状态 |
| `./run-node-demo.sh logs` | 查看 Cloud/register/publisher/client 日志 |
| `./run-node-demo.sh down` | 停止演示进程并释放端口 |

## 运行拓扑

`up` 会启动：

- `cloud/api`：`127.0.0.1:3001`
- publisher demo server：`127.0.0.1:8080`
- `example:publisher-register`：生成 publisher、api key、endpoint id

`smoke` 会运行：

- `sdk/paygate-node/examples/client/pay-per-call.ts`
- 默认走无 RPC 模式（使用 server-prepared tx 路径）

## 运行期文件

输出到 `./.runtime/node-demo/`：

- `env.sh`：本次运行实际使用的环境变量
- `publisher-exports.sh`：register 步骤提取出的导出变量
- `logs/`：`cloud.log`、`register.log`、`publisher.log`、`client.log`
- `pids/`：`cloud.pid`、`publisher.pid`

可直接查看：

```bash
cat .runtime/node-demo/env.sh
```

## 如何用于你自己的本地接入

跑完 `up` 后，你已经有可用的本地 Cloud + API key + endpoint id。接入你自己的应用时：

1. 从 `.runtime/node-demo/env.sh` 读取变量
2. 复用 `PAYGATE_BASE_URL`、`PAYGATE_API_KEY`、`PAYGATE_PUBLISHER_ID`、endpoint id
3. 在你的服务里接入 PayGate challenge/verify 调用

框架接入参考在主仓库：

- `paygate/sdk/paygate-node/examples/`
- `paygate/sdk/paygate-node/README.md`

## 常见问题

### `PAYGATE_REPO_DIR is invalid`

脚本找不到主仓库结构，请确认目录下存在：

- `cloud/api`
- `sdk/paygate-node`

然后设置正确绝对路径：

```bash
export PAYGATE_REPO_DIR="/绝对路径/paygate"
```

### 缺少命令（pnpm/jq 等）

安装缺失命令后重试。

### 端口冲突（3001/8080）

```bash
./run-node-demo.sh down
./run-node-demo.sh up
```

### register 失败或未生成 exports

查看：

```bash
cat .runtime/node-demo/logs/register.log
```

### macOS 下使用 launchctl

脚本在 macOS 可能自动使用 `launchctl` 管理进程。建议通过脚本自身的 `status/down` 管理，不要手工乱杀进程。

## 生产环境提醒

该仓库仅用于本地演示与联调验证。请勿把 demo 默认密钥、mock 结算模式、单机进程策略直接用于生产。
