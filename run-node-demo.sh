#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUNTIME_DIR="${SCRIPT_DIR}/.runtime/node-demo"
LOG_DIR="${RUNTIME_DIR}/logs"
PID_DIR="${RUNTIME_DIR}/pids"
ENV_FILE="${RUNTIME_DIR}/env.sh"
DEFAULT_PAYGATE_REPO_DIR="${SCRIPT_DIR}/../paygate"
PAYGATE_REPO_DIR="${PAYGATE_REPO_DIR:-${DEFAULT_PAYGATE_REPO_DIR}}"
if [[ -d "${PAYGATE_REPO_DIR}" ]]; then
  PAYGATE_REPO_DIR="$(cd "${PAYGATE_REPO_DIR}" && pwd)"
fi

ACTION="${1:-up}"

CLOUD_HOST="127.0.0.1"
CLOUD_PORT="3001"
PUBLISHER_HOST="127.0.0.1"
PUBLISHER_PORT="8080"
CLOUD_BASE_URL="http://${CLOUD_HOST}:${CLOUD_PORT}"
API_URL="http://${PUBLISHER_HOST}:${PUBLISHER_PORT}"
CLOUD_SERVICE_LABEL="com.paygate.demo.cloud"
PUBLISHER_SERVICE_LABEL="com.paygate.demo.publisher"

USE_LAUNCHCTL=false
if [[ "$(uname -s)" == "Darwin" ]] && command -v launchctl >/dev/null 2>&1; then
  USE_LAUNCHCTL=true
fi

# Deterministic local-only wallets for the demo flow.
DEFAULT_PUBLISHER_PK="0x59c6995e998f97a5a0044976f4d1ea9f7567de56b7ec4c596cb8f179f1dc93b3"
DEFAULT_CLIENT_PK="0x8b3a350cf5c34c9194ca3a545d8c5f8a4f5f5f355f2f7f9a3f39f9a2be2d6f75"

PUBLISHER_WALLET_PRIVATE_KEY="${PUBLISHER_WALLET_PRIVATE_KEY:-$DEFAULT_PUBLISHER_PK}"
CLIENT_WALLET_PRIVATE_KEY="${CLIENT_WALLET_PRIVATE_KEY:-$DEFAULT_CLIENT_PK}"

mkdir -p "${LOG_DIR}" "${PID_DIR}"

cloud_pid_file="${PID_DIR}/cloud.pid"
publisher_pid_file="${PID_DIR}/publisher.pid"
register_log="${LOG_DIR}/register.log"
cloud_log="${LOG_DIR}/cloud.log"
publisher_log="${LOG_DIR}/publisher.log"
client_log="${LOG_DIR}/client.log"

print_usage() {
  cat <<'EOF'
Usage:
  ./run-node-demo.sh up      # Start Cloud + register publisher + start demo publisher server
  ./run-node-demo.sh smoke   # Run demo client against the running stack
  ./run-node-demo.sh status  # Show process and endpoint status
  ./run-node-demo.sh logs    # Tail Cloud/publisher logs
  ./run-node-demo.sh down    # Stop Cloud + publisher processes

Env:
  PAYGATE_REPO_DIR=<path-to-paygate-repo>   # default: ../paygate (relative to this script)
EOF
}

ensure_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

ensure_paygate_repo_layout() {
  if [[ ! -d "${PAYGATE_REPO_DIR}/cloud/api" || ! -d "${PAYGATE_REPO_DIR}/sdk/paygate-node" ]]; then
    echo "PAYGATE_REPO_DIR is invalid: ${PAYGATE_REPO_DIR}" >&2
    echo "Expected directories:" >&2
    echo "  ${PAYGATE_REPO_DIR}/cloud/api" >&2
    echo "  ${PAYGATE_REPO_DIR}/sdk/paygate-node" >&2
    exit 1
  fi
}

join_lines_csv() {
  paste -sd "," -
}

pid_is_running() {
  local pid="$1"
  if [[ -z "${pid}" ]]; then
    return 1
  fi
  kill -0 "${pid}" >/dev/null 2>&1
}

read_pid() {
  local file="$1"
  if [[ -f "${file}" ]]; then
    tr -d '[:space:]' <"${file}"
  fi
}

write_pid() {
  local file="$1"
  local pid="$2"
  if [[ -n "${pid}" ]]; then
    echo "${pid}" >"${file}"
  else
    rm -f "${file}"
  fi
}

wait_for_http_ok() {
  local url="$1"
  local timeout_secs="${2:-45}"
  local start_ts
  start_ts="$(date +%s)"

  until curl -fsS "${url}" >/dev/null 2>&1; do
    if [[ $(( "$(date +%s)" - start_ts )) -ge "${timeout_secs}" ]]; then
      echo "Timed out waiting for ${url}" >&2
      return 1
    fi
    sleep 1
  done
}

wait_for_http_stable() {
  local url="$1"
  local checks="${2:-3}"
  local interval_secs="${3:-1}"
  local i
  for (( i=1; i<=checks; i++ )); do
    if ! curl -fsS "${url}" >/dev/null 2>&1; then
      echo "Health check became unstable for ${url} (failed at check ${i}/${checks})" >&2
      return 1
    fi
    sleep "${interval_secs}"
  done
}

port_listener_pids() {
  local port="$1"
  lsof -nP -tiTCP:"${port}" -sTCP:LISTEN 2>/dev/null || true
}

kill_port_listeners() {
  local port="$1"
  local pids
  pids="$(port_listener_pids "${port}")"
  if [[ -z "${pids}" ]]; then
    return 0
  fi

  while IFS= read -r pid; do
    [[ -z "${pid}" ]] && continue
    kill "${pid}" >/dev/null 2>&1 || true
  done <<< "${pids}"

  sleep 1
  pids="$(port_listener_pids "${port}")"
  if [[ -n "${pids}" ]]; then
    while IFS= read -r pid; do
      [[ -z "${pid}" ]] && continue
      kill -9 "${pid}" >/dev/null 2>&1 || true
    done <<< "${pids}"
  fi
}

launchctl_pid() {
  local label="$1"
  launchctl list | awk -v target="${label}" '$3 == target { print $1; exit }'
}

launchctl_is_running() {
  local label="$1"
  local pid
  pid="$(launchctl_pid "${label}")"
  [[ "${pid}" =~ ^[0-9]+$ ]] && pid_is_running "${pid}"
}

service_pid() {
  local label="$1"
  local pid_file="$2"
  if [[ "${USE_LAUNCHCTL}" == "true" ]]; then
    local pid
    pid="$(launchctl_pid "${label}")"
    if [[ "${pid}" =~ ^[0-9]+$ ]]; then
      echo "${pid}"
    fi
  else
    read_pid "${pid_file}"
  fi
}

service_is_running() {
  local label="$1"
  local pid_file="$2"
  if [[ "${USE_LAUNCHCTL}" == "true" ]]; then
    launchctl_is_running "${label}"
  else
    local pid
    pid="$(read_pid "${pid_file}")"
    pid_is_running "${pid}"
  fi
}

start_service() {
  local label="$1"
  local pid_file="$2"
  local log_file="$3"
  local command="$4"

  : >"${log_file}"

  if [[ "${USE_LAUNCHCTL}" == "true" ]]; then
    launchctl remove "${label}" >/dev/null 2>&1 || true
    launchctl submit -l "${label}" -o "${log_file}" -e "${log_file}" -- /bin/sh -lc "${command}"
    sleep 1
    write_pid "${pid_file}" "$(launchctl_pid "${label}")"
  else
    nohup /bin/sh -lc "${command}" >"${log_file}" 2>&1 < /dev/null &
    write_pid "${pid_file}" "$!"
  fi
}

stop_pid_file() {
  local file="$1"
  local pid
  pid="$(read_pid "${file}")"
  if [[ -z "${pid}" ]]; then
    return 0
  fi
  if pid_is_running "${pid}"; then
    kill "${pid}" >/dev/null 2>&1 || true
    for _ in {1..10}; do
      if ! pid_is_running "${pid}"; then
        break
      fi
      sleep 1
    done
    if pid_is_running "${pid}"; then
      kill -9 "${pid}" >/dev/null 2>&1 || true
    fi
  fi
  rm -f "${file}"
}

stop_service() {
  local label="$1"
  local pid_file="$2"
  if [[ "${USE_LAUNCHCTL}" == "true" ]]; then
    launchctl remove "${label}" >/dev/null 2>&1 || true
  fi
  stop_pid_file "${pid_file}"
}

start_cloud() {
  if service_is_running "${CLOUD_SERVICE_LABEL}" "${cloud_pid_file}"; then
    local existing_pid
    existing_pid="$(service_pid "${CLOUD_SERVICE_LABEL}" "${cloud_pid_file}")"
    echo "Cloud already running (pid=${existing_pid:-unknown})"
    return 0
  fi

  start_service "${CLOUD_SERVICE_LABEL}" "${cloud_pid_file}" "${cloud_log}" "cd '${PAYGATE_REPO_DIR}/cloud/api' && \
    HOST='${CLOUD_HOST}' \
    PORT='${CLOUD_PORT}' \
    NODE_ENV='development' \
    TOKEN_SECRET='demo-local-secret' \
    PAYGATE_BASE_URL='${CLOUD_BASE_URL}' \
    VERIFICATION_MODE='mock' \
    SETTLEMENT_MODE='mock' \
    pnpm dev"

  wait_for_http_ok "${CLOUD_BASE_URL}/health" 60
  wait_for_http_stable "${CLOUD_BASE_URL}/health" 4 1
}

register_publisher() {
  : >"${register_log}"
  (
    cd "${PAYGATE_REPO_DIR}/sdk/paygate-node"
    PAYGATE_BASE_URL="${CLOUD_BASE_URL}" \
    PAYGATE_CHAIN_ID="8453" \
    PUBLISHER_WALLET_PRIVATE_KEY="${PUBLISHER_WALLET_PRIVATE_KEY}" \
    pnpm example:publisher-register
  ) >"${register_log}" 2>&1

  local exports_file="${RUNTIME_DIR}/publisher-exports.sh"
  grep '^export PAYGATE_' "${register_log}" >"${exports_file}" || true
  if [[ ! -s "${exports_file}" ]]; then
    echo "Failed to extract publisher exports. Check ${register_log}" >&2
    exit 1
  fi

  # shellcheck source=/dev/null
  source "${exports_file}"

  cat >"${ENV_FILE}" <<EOF
export CLOUD_BASE_URL='${CLOUD_BASE_URL}'
export API_URL='${API_URL}'
export PUBLISHER_WALLET_PRIVATE_KEY='${PUBLISHER_WALLET_PRIVATE_KEY}'
export CLIENT_WALLET_PRIVATE_KEY='${CLIENT_WALLET_PRIVATE_KEY}'
export PAYGATE_API_KEY='${PAYGATE_API_KEY}'
export PAYGATE_PUBLISHER_ID='${PAYGATE_PUBLISHER_ID}'
export PAYGATE_WEATHER_ENDPOINT_ID='${PAYGATE_WEATHER_ENDPOINT_ID}'
export PAYGATE_ECHO_ENDPOINT_ID='${PAYGATE_ECHO_ENDPOINT_ID}'
EOF
}

start_publisher_server() {
  # shellcheck source=/dev/null
  source "${ENV_FILE}"

  if service_is_running "${PUBLISHER_SERVICE_LABEL}" "${publisher_pid_file}"; then
    local existing_pid
    existing_pid="$(service_pid "${PUBLISHER_SERVICE_LABEL}" "${publisher_pid_file}")"
    echo "Publisher server already running (pid=${existing_pid:-unknown})"
    return 0
  fi

  start_service "${PUBLISHER_SERVICE_LABEL}" "${publisher_pid_file}" "${publisher_log}" "cd '${PAYGATE_REPO_DIR}/sdk/paygate-node' && \
    PAYGATE_BASE_URL='${CLOUD_BASE_URL}' \
    PAYGATE_API_KEY='${PAYGATE_API_KEY}' \
    PAYGATE_PUBLISHER_ID='${PAYGATE_PUBLISHER_ID}' \
    PAYGATE_WEATHER_ENDPOINT_ID='${PAYGATE_WEATHER_ENDPOINT_ID}' \
    PAYGATE_ECHO_ENDPOINT_ID='${PAYGATE_ECHO_ENDPOINT_ID}' \
    pnpm example:publisher-server-express"

  wait_for_http_ok "${API_URL}/health" 60
  wait_for_http_stable "${API_URL}/health" 4 1
}

cmd_up() {
  ensure_paygate_repo_layout
  ensure_cmd pnpm
  ensure_cmd curl
  ensure_cmd jq
  ensure_cmd lsof
  start_cloud
  register_publisher
  start_publisher_server
  cmd_status
}

cmd_smoke() {
  ensure_paygate_repo_layout
  ensure_cmd pnpm
  if [[ ! -f "${ENV_FILE}" ]]; then
    echo "Missing ${ENV_FILE}. Run './run-node-demo.sh up' first." >&2
    exit 1
  fi
  # shellcheck source=/dev/null
  source "${ENV_FILE}"

  : >"${client_log}"
  (
    cd "${PAYGATE_REPO_DIR}/sdk/paygate-node"
    PAYGATE_BASE_URL="${CLOUD_BASE_URL}" \
    API_URL="${API_URL}" \
    CLIENT_WALLET_PRIVATE_KEY="${CLIENT_WALLET_PRIVATE_KEY}" \
    pnpm example:client
  ) | tee "${client_log}"
}

cmd_status() {
  local cloud_pid publisher_pid
  cloud_pid="$(service_pid "${CLOUD_SERVICE_LABEL}" "${cloud_pid_file}")"
  publisher_pid="$(service_pid "${PUBLISHER_SERVICE_LABEL}" "${publisher_pid_file}")"

  echo "runtime_dir=${RUNTIME_DIR}"
  echo "paygate_repo_dir=${PAYGATE_REPO_DIR}"
  echo "launcher=$([[ "${USE_LAUNCHCTL}" == "true" ]] && echo "launchctl" || echo "nohup")"
  if service_is_running "${CLOUD_SERVICE_LABEL}" "${cloud_pid_file}"; then
    echo "cloud=running pid=${cloud_pid}"
  else
    echo "cloud=stopped"
  fi
  if service_is_running "${PUBLISHER_SERVICE_LABEL}" "${publisher_pid_file}"; then
    echo "publisher=running pid=${publisher_pid}"
  else
    echo "publisher=stopped"
  fi

  local cloud_port_pids publisher_port_pids
  cloud_port_pids="$(port_listener_pids "${CLOUD_PORT}")"
  publisher_port_pids="$(port_listener_pids "${PUBLISHER_PORT}")"
  if [[ -n "${cloud_port_pids}" ]]; then
    echo "cloud_port=listen port=${CLOUD_PORT} pid=$(printf '%s\n' "${cloud_port_pids}" | join_lines_csv)"
  else
    echo "cloud_port=down port=${CLOUD_PORT}"
  fi
  if [[ -n "${publisher_port_pids}" ]]; then
    echo "publisher_port=listen port=${PUBLISHER_PORT} pid=$(printf '%s\n' "${publisher_port_pids}" | join_lines_csv)"
  else
    echo "publisher_port=down port=${PUBLISHER_PORT}"
  fi

  if curl -fsS "${CLOUD_BASE_URL}/health" >/dev/null 2>&1; then
    echo "cloud_health=ok ${CLOUD_BASE_URL}/health"
  else
    echo "cloud_health=down ${CLOUD_BASE_URL}/health"
  fi

  if curl -fsS "${API_URL}/health" >/dev/null 2>&1; then
    echo "publisher_health=ok ${API_URL}/health"
  else
    echo "publisher_health=down ${API_URL}/health"
  fi
}

cmd_logs() {
  tail -n 120 "${cloud_log}" "${register_log}" "${publisher_log}" "${client_log}" 2>/dev/null || true
}

cmd_down() {
  stop_service "${PUBLISHER_SERVICE_LABEL}" "${publisher_pid_file}"
  stop_service "${CLOUD_SERVICE_LABEL}" "${cloud_pid_file}"
  kill_port_listeners "${PUBLISHER_PORT}"
  kill_port_listeners "${CLOUD_PORT}"
  echo "Stopped demo processes."
}

case "${ACTION}" in
  up)
    cmd_up
    ;;
  smoke)
    cmd_smoke
    ;;
  status)
    cmd_status
    ;;
  logs)
    cmd_logs
    ;;
  down)
    cmd_down
    ;;
  *)
    print_usage
    exit 1
    ;;
esac
