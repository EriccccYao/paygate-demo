# PayGate Demo

Language: [English](./README.md) | [简体中文](./README.zh-CN.md) | [日本語](./README.ja.md)

Official demo entry: **https://paygate.deltab.ai**

This repository is for running a reproducible local PayGate payment demo flow.

## SDK Integration (Production)

Current npm packages (already published):

```bash
npm i @deltablab/express @deltablab/client-fetch ethers
# or
pnpm add @deltablab/express @deltablab/client-fetch ethers
```

Integration model:

1. Publisher protects routes with `@deltablab/express` (or `@deltablab/hono` / `@deltablab/next`)
2. Client calls paid routes using `@deltablab/client-fetch`
3. Runtime flow is `402 challenge -> sign -> retry -> 200`

## Product Demo Goal

Show the end-to-end pay-per-call loop:

1. client calls protected endpoint
2. server returns `402` challenge
3. client signs payment proof
4. client retries
5. server returns `200`

Demo endpoints:

- `GET /v1/weather`
- `POST /v1/echo`

## Prerequisites

- macOS or Linux
- Node.js 20+
- `pnpm`, `curl`, `jq`, `lsof`
- local PayGate source tree path that contains:
  - `cloud/api`
  - `sdk/paygate-node`

Set runtime path:

```bash
export PAYGATE_REPO_DIR="/absolute/path/to/paygate-source"
```

## One-Time Setup

```bash
cd "$PAYGATE_REPO_DIR/cloud/api"
pnpm install

cd "$PAYGATE_REPO_DIR/sdk/paygate-node"
pnpm install
```

## Quick Start

From this repo root:

```bash
./run-node-demo.sh up
./run-node-demo.sh smoke
```

Stop:

```bash
./run-node-demo.sh down
```

## Commands

| Command | Purpose |
|---|---|
| `./run-node-demo.sh up` | Start Cloud API + register publisher/endpoints + start publisher demo server |
| `./run-node-demo.sh smoke` | Run client payment flow against the running stack |
| `./run-node-demo.sh status` | Show process/port/health state |
| `./run-node-demo.sh logs` | Show Cloud/register/publisher/client logs |
| `./run-node-demo.sh down` | Stop demo processes and free ports |

## Runtime Topology

`up` starts:

- PayGate Cloud API at `127.0.0.1:3001`
- Publisher demo server at `127.0.0.1:8080`
- Publisher bootstrap step that creates:
  - publisher
  - API key
  - paid endpoint IDs

`smoke` runs the client demo script in no-RPC mode by default (server-prepared tx path).

## Runtime Artifacts

Generated under `./.runtime/node-demo/`:

- `env.sh`
- `publisher-exports.sh`
- `logs/` (`cloud.log`, `register.log`, `publisher.log`, `client.log`)
- `pids/` (`cloud.pid`, `publisher.pid`)

## Troubleshooting

### `PAYGATE_REPO_DIR is invalid`

Make sure `PAYGATE_REPO_DIR` points to a source tree with both folders:

- `cloud/api`
- `sdk/paygate-node`

### Tool missing (`pnpm`, `jq`, etc.)

Install missing tools, then rerun.

### Port conflict (`3001` or `8080`)

```bash
./run-node-demo.sh down
./run-node-demo.sh up
```

### Register step failed

```bash
cat .runtime/node-demo/logs/register.log
```

## Production Note

This repository is for demo and local integration validation. Do not reuse demo defaults directly in production.
