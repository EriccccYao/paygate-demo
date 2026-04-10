# PayGate Demo

Language: [English](./README.md) | [简体中文](./README.zh-CN.md) | [日本語](./README.ja.md)

Standalone runnable demo for the PayGate Node publisher + client payment flow.

This repository is intentionally small: it contains the demo runner and docs. The actual PayGate Cloud/API/SDK code lives in the main repository:

- https://github.com/tomo-inc/paygate

## What This Repository Is For

Use this repo when you want a fast, repeatable local demo of the full payment loop:

1. client calls paid endpoint
2. server returns `402` challenge
3. client signs payment proof
4. client retries request
5. server returns success (`200`)

Demo endpoints in the flow:

- `GET /v1/weather`
- `POST /v1/echo`

## Scope Boundary

This repository does **not** include PayGate source code. It orchestrates code in your local `paygate` checkout.

- Demo orchestrator: `./run-node-demo.sh`
- Runtime outputs: `./.runtime/node-demo/`
- Placeholder docs:
  - `./publisher-node-demo/README.md`
  - `./publisher-python-demo/README.md`
  - `./agent-client-demo/README.md`

## Prerequisites

- macOS or Linux shell
- Node.js 20+
- `pnpm`
- `curl`
- `jq`
- `lsof`
- local checkout of `paygate` repository

## Recommended Workspace Layout

```text
<workspace>/
  paygate/        # https://github.com/tomo-inc/paygate
  paygate-demo/   # this repository
```

If your layout is different, set `PAYGATE_REPO_DIR` explicitly.

## One-Time Setup

In the main `paygate` repo, install dependencies:

```bash
cd ../paygate

# cloud api
cd cloud/api
pnpm install

# node sdk/examples
cd ../../sdk/paygate-node
pnpm install
```

## Quick Start

From `paygate-demo` root:

```bash
# optional if paygate repo is not ../paygate
export PAYGATE_REPO_DIR="/absolute/path/to/paygate"

./run-node-demo.sh up
./run-node-demo.sh smoke
```

Teardown:

```bash
./run-node-demo.sh down
```

## Command Reference

| Command | Purpose |
|---|---|
| `./run-node-demo.sh up` | Start Cloud API + register publisher/endpoints + start publisher demo server |
| `./run-node-demo.sh smoke` | Run client demo against running stack |
| `./run-node-demo.sh status` | Show pids, port listeners, and health status |
| `./run-node-demo.sh logs` | Tail Cloud/register/publisher/client logs |
| `./run-node-demo.sh down` | Stop demo processes and free ports |

## Runtime Topology

`up` starts:

- PayGate Cloud API (`cloud/api`) at `127.0.0.1:3001`
- Demo publisher server (`sdk/paygate-node/examples/publisher/server-express.ts`) at `127.0.0.1:8080`
- Publisher bootstrap (`example:publisher-register`) that creates:
  - publisher
  - API key
  - paid endpoint IDs

`smoke` runs:

- `sdk/paygate-node/examples/client/pay-per-call.ts`
- default mode: no client RPC required (server-prepared tx path)

## Runtime Files

Generated under `./.runtime/node-demo/`:

- `env.sh`: resolved runtime env vars
- `publisher-exports.sh`: exports produced by register step
- `logs/`:
  - `cloud.log`
  - `register.log`
  - `publisher.log`
  - `client.log`
- `pids/`:
  - `cloud.pid`
  - `publisher.pid`

You can inspect values used by the demo:

```bash
cat .runtime/node-demo/env.sh
```

## Integration Notes (How To Reuse In Your Own App)

After `up`, your local PayGate Cloud and demo publisher are running with valid credentials and endpoint IDs. Reuse these to wire your own local app quickly:

1. read generated values from `.runtime/node-demo/env.sh`
2. use `PAYGATE_BASE_URL`, `PAYGATE_API_KEY`, `PAYGATE_PUBLISHER_ID`, and endpoint IDs
3. configure your app/middleware to call PayGate Cloud challenge/verify APIs

For framework-specific examples, see the main repo:

- `paygate/sdk/paygate-node/examples/`
- `paygate/sdk/paygate-node/README.md`

## Troubleshooting

### `PAYGATE_REPO_DIR is invalid`

Your path does not point to a PayGate checkout with both directories:

- `cloud/api`
- `sdk/paygate-node`

Fix by exporting the correct absolute path:

```bash
export PAYGATE_REPO_DIR="/absolute/path/to/paygate"
```

### Missing tool (`pnpm`, `jq`, etc.)

Install the missing command, then rerun.

### Port already in use (`3001` or `8080`)

Run:

```bash
./run-node-demo.sh down
./run-node-demo.sh up
```

### Register step failed / no exports found

Check:

```bash
cat .runtime/node-demo/logs/register.log
```

### On macOS: process managed by `launchctl`

The script may use `launchctl` automatically. Use `status`/`down` from this script instead of killing random pids manually.

## Production Reminder

This demo is for local development and integration validation only. Do not treat demo keys, local process strategy, or mock settlement mode as production deployment guidance.
