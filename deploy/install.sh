#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
SERVICE_NAME="icloud-hme"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
INSTALL_DIR="/opt/${SERVICE_NAME}"
DATA_DIR="/var/lib/${SERVICE_NAME}"
CONFIG_DIR="/etc/${SERVICE_NAME}"
ENV_FILE="${CONFIG_DIR}/${SERVICE_NAME}.env"

log() {
  printf '==> %s\n' "$*"
}

die() {
  printf '错误: %s\n' "$*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "缺少命令: $1"
}

if [[ "$(uname -m)" != "x86_64" ]]; then
  die "此脚本仅支持 x86_64 服务器，当前架构: $(uname -m)"
fi

for command_name in go systemctl openssl install useradd getent curl; do
  require_command "${command_name}"
done

if (( EUID == 0 )); then
  SUDO=()
else
  require_command sudo
  SUDO=(sudo)
  "${SUDO[@]}" -v
fi

log "编译 Linux amd64 二进制"
(
  cd "${PROJECT_ROOT}"
  GOARCH=amd64 bash build.sh
)

BINARY="${PROJECT_ROOT}/build/${SERVICE_NAME}"
[[ -x "${BINARY}" ]] || die "构建产物不存在: ${BINARY}"

log "创建服务用户和部署目录"
if ! id "${SERVICE_NAME}" >/dev/null 2>&1; then
  NOLOGIN_SHELL="$(command -v nologin || true)"
  [[ -n "${NOLOGIN_SHELL}" ]] || NOLOGIN_SHELL="/usr/sbin/nologin"
  if getent group "${SERVICE_NAME}" >/dev/null 2>&1; then
    "${SUDO[@]}" useradd --system --gid "${SERVICE_NAME}" \
      --home-dir "${DATA_DIR}" --shell "${NOLOGIN_SHELL}" "${SERVICE_NAME}"
  else
    "${SUDO[@]}" useradd --system --user-group \
      --home-dir "${DATA_DIR}" --shell "${NOLOGIN_SHELL}" "${SERVICE_NAME}"
  fi
fi

"${SUDO[@]}" install -d -m 0750 -o "${SERVICE_NAME}" -g "${SERVICE_NAME}" \
  "${INSTALL_DIR}" "${DATA_DIR}"
"${SUDO[@]}" chown -R "${SERVICE_NAME}:${SERVICE_NAME}" "${DATA_DIR}"

if "${SUDO[@]}" test -f "${PROJECT_ROOT}/data/accounts.json" && \
    ! "${SUDO[@]}" test -e "${DATA_DIR}/accounts.json"; then
  log "迁移现有 data/accounts.json"
  "${SUDO[@]}" install -m 0600 -o "${SERVICE_NAME}" -g "${SERVICE_NAME}" \
    "${PROJECT_ROOT}/data/accounts.json" "${DATA_DIR}/accounts.json"
fi

log "安装程序和 systemd 服务"
"${SUDO[@]}" systemctl stop "${SERVICE_NAME}.service" 2>/dev/null || true
"${SUDO[@]}" install -m 0755 "${BINARY}" "${INSTALL_DIR}/${SERVICE_NAME}"
"${SUDO[@]}" install -m 0644 "${SCRIPT_DIR}/${SERVICE_NAME}.service" "${SERVICE_FILE}"
"${SUDO[@]}" install -d -m 0750 "${CONFIG_DIR}"

if ! "${SUDO[@]}" test -f "${ENV_FILE}"; then
  API_KEY="$(openssl rand -hex 32)"
  printf 'API_KEY=%s\n' "${API_KEY}" | "${SUDO[@]}" tee "${ENV_FILE}" >/dev/null
  log "已生成 API Key，可执行以下命令查看"
  printf '    sudo cat %s\n' "${ENV_FILE}"
else
  log "保留现有 API Key: ${ENV_FILE}"
fi
"${SUDO[@]}" chmod 0600 "${ENV_FILE}"

log "启动服务"
"${SUDO[@]}" systemctl daemon-reload
"${SUDO[@]}" systemctl enable --now "${SERVICE_NAME}.service"

HEALTHY=false
for _ in {1..10}; do
  if curl --fail --silent http://127.0.0.1:8081/healthz >/dev/null; then
    HEALTHY=true
    break
  fi
  sleep 1
done

if [[ "${HEALTHY}" != true ]]; then
  "${SUDO[@]}" journalctl -u "${SERVICE_NAME}.service" -n 50 --no-pager || true
  die "服务健康检查失败，请确认 8081 端口未被 Docker 或其他程序占用"
fi

log "部署完成"
printf '    状态: sudo systemctl status %s\n' "${SERVICE_NAME}"
printf '    日志: sudo journalctl -u %s -f\n' "${SERVICE_NAME}"
printf '    健康检查: curl http://127.0.0.1:8081/healthz\n'
