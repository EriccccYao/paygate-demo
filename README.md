# PayGate Demo

Standalone demo runner for the PayGate Node publisher/client flow.

This repository now hosts demo assets that used to live under `paygate/demo/`.

## Prerequisites

- `pnpm`, `curl`, `jq`, `lsof`
- Local checkout of the main PayGate repo: `https://github.com/tomo-inc/paygate`

Default expected layout:

```text
<workspace>/
  paygate/        # main repo
  paygate-demo/   # this repo
```

If your layout is different, set `PAYGATE_REPO_DIR`.

## Quick start

From this repository root:

```bash
./run-node-demo.sh up
./run-node-demo.sh smoke
```

Status/logs/teardown:

```bash
./run-node-demo.sh status
./run-node-demo.sh logs
./run-node-demo.sh down
```

## Runtime behavior

The script starts:

- PayGate Cloud API (`cloud/api`) on `127.0.0.1:3001`
- Publisher demo server (`sdk/paygate-node/examples/publisher/server-express.ts`) on `127.0.0.1:8080`
- Publisher bootstrap (`example:publisher-register`) to create publisher + paid endpoints
- Client payment flow (`example:client`) for:
  - `GET /v1/weather`
  - `POST /v1/echo`

By default, client runs in no-RPC mode (server-prepared unsigned tx via `relay_prepare_url`).

## Runtime artifacts

- Runtime files are written under `.runtime/node-demo/`:
  - `pids/` for Cloud/publisher process ids
  - `logs/` for Cloud/register/publisher/client output
  - `env.sh` with resolved local demo env vars
