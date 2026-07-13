#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
SERVICE_NAME="icloud-hme"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
BASE_DIR="/opt/${SERVICE_NAME}"
BIN_DIR="${BASE_DIR}/bin"
DATA_DIR="${BASE_DIR}/data"
CONFIG_DIR="${BASE_DIR}/config"
ENV_FILE="${CONFIG_DIR}/${SERVICE_NAME}.env"
LEGACY_DATA_DIR="/var/lib/${SERVICE_NAME}"
LEGACY_CONFIG_DIR="/etc/${SERVICE_NAME}"
MIGRATED_DATA=false
MIGRATED_CONFIG=false
MIN_GO_MAJOR=1
MIN_GO_MINOR=26
GO_TMP_DIR=""

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

cleanup() {
  if [[ -n "${GO_TMP_DIR}" && -d "${GO_TMP_DIR}" ]]; then
    rm -rf "${GO_TMP_DIR}"
  fi
}

go_version_supported() {
  local version="${1#go}"
  if [[ ! "${version}" =~ ^([0-9]+)\.([0-9]+) ]]; then
    return 1
  fi

  local major="${BASH_REMATCH[1]}"
  local minor="${BASH_REMATCH[2]}"
  (( major > MIN_GO_MAJOR || (major == MIN_GO_MAJOR && minor >= MIN_GO_MINOR) ))
}

install_go() {
  local version_response checksum_response go_version archive checksum

  for command_name in tar sha256sum mktemp; do
    require_command "${command_name}"
  done

  log "获取 Go 官方最新稳定版本"
  version_response="$(curl --fail --silent --show-error --location \
    'https://go.dev/VERSION?m=text')"
  go_version="${version_response%%$'\n'*}"
  go_version_supported "${go_version}" || \
    die "Go 官方最新版本不满足 ${MIN_GO_MAJOR}.${MIN_GO_MINOR} 要求: ${go_version}"

  archive="${go_version}.linux-amd64.tar.gz"
  GO_TMP_DIR="$(mktemp -d)"

  log "下载并校验 ${go_version}"
  curl --fail --silent --show-error --location --retry 3 \
    "https://dl.google.com/go/${archive}" -o "${GO_TMP_DIR}/${archive}"
  checksum_response="$(curl --fail --silent --show-error --location --retry 3 \
    "https://dl.google.com/go/${archive}.sha256")"
  if [[ "${checksum_response}" =~ (^|[[:space:]])([0-9a-fA-F]{64})([[:space:]]|$) ]]; then
    checksum="${BASH_REMATCH[2],,}"
  else
    die "Go SHA256 响应中未找到有效哈希"
  fi
  (
    cd "${GO_TMP_DIR}"
    printf '%s  %s\n' "${checksum}" "${archive}" | sha256sum --check --status
  ) || die "Go 安装包 SHA256 校验失败"

  log "安装 ${go_version} 到 /usr/local/go"
  "${SUDO[@]}" rm -rf /usr/local/go
  "${SUDO[@]}" install -d -m 0755 /usr/local /usr/local/bin
  "${SUDO[@]}" tar -C /usr/local -xzf "${GO_TMP_DIR}/${archive}"
  "${SUDO[@]}" ln -sfn /usr/local/go/bin/go /usr/local/bin/go
  export PATH="/usr/local/go/bin:${PATH}"
  hash -r

  go_version_supported "$(go env GOVERSION)" || die "Go 安装完成但版本检查失败"
}

trap cleanup EXIT

if [[ "$(uname -m)" != "x86_64" ]]; then
  die "此脚本仅支持 x86_64 服务器，当前架构: $(uname -m)"
fi

for command_name in systemctl openssl install useradd getent curl; do
  require_command "${command_name}"
done

if (( EUID == 0 )); then
  SUDO=()
else
  require_command sudo
  SUDO=(sudo)
  "${SUDO[@]}" -v
fi

if ! command -v go >/dev/null 2>&1; then
  log "未检测到 Go，准备自动安装"
  install_go
elif ! go_version_supported "$(go env GOVERSION 2>/dev/null || true)"; then
  log "当前 Go 版本低于 ${MIN_GO_MAJOR}.${MIN_GO_MINOR}，准备自动升级"
  install_go
else
  log "使用现有 $(go env GOVERSION)"
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

"${SUDO[@]}" install -d -m 0755 "${BASE_DIR}" "${BIN_DIR}"
"${SUDO[@]}" install -d -m 0750 -o "${SERVICE_NAME}" -g "${SERVICE_NAME}" "${DATA_DIR}"
"${SUDO[@]}" install -d -m 0750 "${CONFIG_DIR}"
"${SUDO[@]}" chown root:root "${BASE_DIR}" "${BIN_DIR}" "${CONFIG_DIR}"
"${SUDO[@]}" chmod 0755 "${BASE_DIR}" "${BIN_DIR}"
"${SUDO[@]}" chmod 0750 "${CONFIG_DIR}"
"${SUDO[@]}" chown -R "${SERVICE_NAME}:${SERVICE_NAME}" "${DATA_DIR}"

"${SUDO[@]}" systemctl stop "${SERVICE_NAME}.service" 2>/dev/null || true

if ! "${SUDO[@]}" test -e "${DATA_DIR}/accounts.json"; then
  if "${SUDO[@]}" test -f "${LEGACY_DATA_DIR}/accounts.json"; then
    log "迁移 ${LEGACY_DATA_DIR}/accounts.json"
    "${SUDO[@]}" install -m 0600 -o "${SERVICE_NAME}" -g "${SERVICE_NAME}" \
      "${LEGACY_DATA_DIR}/accounts.json" "${DATA_DIR}/accounts.json"
    MIGRATED_DATA=true
  elif "${SUDO[@]}" test -f "${PROJECT_ROOT}/data/accounts.json"; then
    log "迁移仓库内的 data/accounts.json"
    "${SUDO[@]}" install -m 0600 -o "${SERVICE_NAME}" -g "${SERVICE_NAME}" \
      "${PROJECT_ROOT}/data/accounts.json" "${DATA_DIR}/accounts.json"
  fi
fi

log "安装程序和 systemd 服务"
"${SUDO[@]}" install -m 0755 "${BINARY}" "${BIN_DIR}/${SERVICE_NAME}"
"${SUDO[@]}" install -m 0644 "${SCRIPT_DIR}/${SERVICE_NAME}.service" "${SERVICE_FILE}"

if ! "${SUDO[@]}" test -f "${ENV_FILE}"; then
  if "${SUDO[@]}" test -f "${LEGACY_CONFIG_DIR}/${SERVICE_NAME}.env"; then
    log "迁移 ${LEGACY_CONFIG_DIR}/${SERVICE_NAME}.env"
    "${SUDO[@]}" install -m 0600 \
      "${LEGACY_CONFIG_DIR}/${SERVICE_NAME}.env" "${ENV_FILE}"
    MIGRATED_CONFIG=true
  else
    API_KEY="$(openssl rand -hex 32)"
    printf 'API_KEY=%s\n' "${API_KEY}" | "${SUDO[@]}" tee "${ENV_FILE}" >/dev/null
    log "已生成 API Key，可执行以下命令查看"
    printf '    sudo cat %s\n' "${ENV_FILE}"
  fi
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

if [[ "${MIGRATED_DATA}" == true ]]; then
  "${SUDO[@]}" rm -f "${LEGACY_DATA_DIR}/accounts.json"
  "${SUDO[@]}" rmdir "${LEGACY_DATA_DIR}" 2>/dev/null || true
fi
if [[ "${MIGRATED_CONFIG}" == true ]]; then
  "${SUDO[@]}" rm -f "${LEGACY_CONFIG_DIR}/${SERVICE_NAME}.env"
  "${SUDO[@]}" rmdir "${LEGACY_CONFIG_DIR}" 2>/dev/null || true
fi
"${SUDO[@]}" rm -f "${BASE_DIR}/${SERVICE_NAME}"

log "部署完成"
printf '    状态: sudo systemctl status %s\n' "${SERVICE_NAME}"
printf '    日志: sudo journalctl -u %s -f\n' "${SERVICE_NAME}"
printf '    健康检查: curl http://127.0.0.1:8081/healthz\n'
