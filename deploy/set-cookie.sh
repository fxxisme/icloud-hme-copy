#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
COOKIE_FILE="${COOKIE_FILE:-${SCRIPT_DIR}/cookie.txt}"
ENV_FILE="/opt/icloud-hme/config/icloud-hme.env"
SERVICE_URL="${SERVICE_URL:-http://127.0.0.1:8081}"
ACCOUNT_ID=""
RESPONSE_FILE=""

usage() {
  cat <<'EOF'
用法:
  ./deploy/set-cookie.sh
  ./deploy/set-cookie.sh --id ACCOUNT_ID

首次导入会根据 real_email 自动使用邮箱前缀作为账号名称。
Cookie 失效后，使用 --id 更新已有账号，避免重复创建。
EOF
}

die() {
  printf '错误: %s\n' "$*" >&2
  exit 1
}

cleanup() {
  if [[ -n "${RESPONSE_FILE}" && -f "${RESPONSE_FILE}" ]]; then
    rm -f "${RESPONSE_FILE}"
  fi
}

case "${1:-}" in
  "") ;;
  -h|--help) usage; exit 0 ;;
  --id)
    [[ -n "${2:-}" && -z "${3:-}" ]] || { usage >&2; exit 1; }
    ACCOUNT_ID="$2"
    ;;
  *) usage >&2; exit 1 ;;
esac

for command_name in curl sed grep mktemp install chmod cat rm; do
  command -v "${command_name}" >/dev/null 2>&1 || die "缺少命令: ${command_name}"
done

if [[ ! -f "${COOKIE_FILE}" ]]; then
  install -m 0600 "${SCRIPT_DIR}/cookie.txt.example" "${COOKIE_FILE}"
  die "已创建 ${COOKIE_FILE}，请填写 Cookie JSON 后重新运行"
fi
chmod 0600 "${COOKIE_FILE}"
[[ -s "${COOKIE_FILE}" ]] || die "Cookie 文件为空: ${COOKIE_FILE}"
if grep -q 'YOUR_.*_HERE' "${COOKIE_FILE}"; then
  die "请先将 Application → Cookies 导出的真实值填入 ${COOKIE_FILE}"
fi

if (( EUID == 0 )); then
  SUDO=()
else
  command -v sudo >/dev/null 2>&1 || die "无法读取 API Key：缺少 sudo"
  SUDO=(sudo)
fi

API_KEY="$("${SUDO[@]}" sed -n 's/^API_KEY=//p' "${ENV_FILE}")"
[[ -n "${API_KEY}" ]] || die "无法从 ${ENV_FILE} 读取 API Key"

FORM_ARGS=(--form "cookies=<${COOKIE_FILE}")
if [[ -n "${ACCOUNT_ID}" ]]; then
  FORM_ARGS+=(--form-string "id=${ACCOUNT_ID}")
else
  FORM_ARGS+=(--form-string "name=iCloud" --form-string "host=icloud.com")
fi

RESPONSE_FILE="$(mktemp)"
trap cleanup EXIT
if ! HTTP_CODE="$(curl --silent --show-error \
  --output "${RESPONSE_FILE}" --write-out '%{http_code}' \
  --request POST "${SERVICE_URL}/api/accounts/import-cookie" \
  --header "Authorization: Bearer ${API_KEY}" \
  "${FORM_ARGS[@]}")"; then
  die "请求服务失败: ${SERVICE_URL}"
fi

cat "${RESPONSE_FILE}"
printf '\n'
if [[ "${HTTP_CODE}" =~ ^2[0-9]{2}$ ]]; then
  : > "${COOKIE_FILE}"
  printf 'Cookie 设置成功，已清空 %s\n' "${COOKIE_FILE}"
else
  die "Cookie 设置失败，HTTP ${HTTP_CODE}；原文件已保留"
fi
