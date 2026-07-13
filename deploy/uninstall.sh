#!/usr/bin/env bash

set -Eeuo pipefail

SERVICE_NAME="icloud-hme"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
INSTALL_DIR="/opt/${SERVICE_NAME}"
DATA_DIR="/var/lib/${SERVICE_NAME}"
CONFIG_DIR="/etc/${SERVICE_NAME}"
PURGE=false

usage() {
  cat <<'EOF'
用法: bash deploy/uninstall.sh [--purge]

默认保留 /var/lib/icloud-hme 和 /etc/icloud-hme。
使用 --purge 同时删除账号数据和 API Key。
EOF
}

case "${1:-}" in
  "") ;;
  --purge) PURGE=true ;;
  -h|--help) usage; exit 0 ;;
  *) usage >&2; exit 1 ;;
esac

if (( EUID == 0 )); then
  SUDO=()
else
  command -v sudo >/dev/null 2>&1 || {
    printf '错误: 缺少命令: sudo\n' >&2
    exit 1
  }
  SUDO=(sudo)
  "${SUDO[@]}" -v
fi

printf '==> 停止并移除 systemd 服务\n'
"${SUDO[@]}" systemctl disable --now "${SERVICE_NAME}.service" 2>/dev/null || true
"${SUDO[@]}" rm -f "${SERVICE_FILE}"
"${SUDO[@]}" rm -rf "${INSTALL_DIR}"
"${SUDO[@]}" systemctl daemon-reload
"${SUDO[@]}" systemctl reset-failed "${SERVICE_NAME}.service" 2>/dev/null || true

if id "${SERVICE_NAME}" >/dev/null 2>&1; then
  "${SUDO[@]}" userdel "${SERVICE_NAME}"
fi
if getent group "${SERVICE_NAME}" >/dev/null 2>&1; then
  "${SUDO[@]}" groupdel "${SERVICE_NAME}" 2>/dev/null || true
fi

if [[ "${PURGE}" == true ]]; then
  printf '==> 删除账号数据和 API Key\n'
  "${SUDO[@]}" rm -rf "${DATA_DIR}" "${CONFIG_DIR}"
else
  printf '==> 已保留数据: %s\n' "${DATA_DIR}"
  printf '==> 已保留配置: %s\n' "${CONFIG_DIR}"
fi

printf '==> 卸载完成\n'
