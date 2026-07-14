#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${ENV_FILE:-/opt/icloud-hme/config/icloud-hme.env}"
SERVICE_URL="${SERVICE_URL:-http://127.0.0.1:8081}"
COOKIE_FILE="${COOKIE_FILE:-${SCRIPT_DIR}/cookie.txt}"
CURRENT_ACCOUNT_ID=""
RESPONSE_FILE=""

usage() {
  cat <<'EOF'
用法: ./deploy/menu.sh

启动 iCloud HME 交互菜单。服务地址可通过 SERVICE_URL 覆盖。
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

pause() {
  printf '\n'
  read -r -p "按回车继续..." _
}

print_response() {
  if command -v jq >/dev/null 2>&1; then
    jq . "${RESPONSE_FILE}" 2>/dev/null || cat "${RESPONSE_FILE}"
  else
    cat "${RESPONSE_FILE}"
  fi
  printf '\n'
}

api_call() {
  local method="$1"
  local path="$2"
  local http_code
  shift 2

  RESPONSE_FILE="$(mktemp)"
  if ! http_code="$(curl --silent --show-error \
    --output "${RESPONSE_FILE}" --write-out '%{http_code}' \
    --request "${method}" "${SERVICE_URL}${path}" \
    --header "Authorization: Bearer ${API_KEY}" "$@")"; then
    printf '请求服务失败: %s\n' "${SERVICE_URL}" >&2
    rm -f "${RESPONSE_FILE}"
    RESPONSE_FILE=""
    return 1
  fi

  print_response
  rm -f "${RESPONSE_FILE}"
  RESPONSE_FILE=""
  [[ "${http_code}" =~ ^2[0-9]{2}$ ]]
}

read_account_id() {
  local prompt="请输入账号 ID"
  if [[ -n "${CURRENT_ACCOUNT_ID}" ]]; then
    prompt+="（回车使用 ${CURRENT_ACCOUNT_ID}）"
  fi
  read -r -p "${prompt}: " ACCOUNT_ID
  ACCOUNT_ID="${ACCOUNT_ID:-${CURRENT_ACCOUNT_ID}}"
  if [[ -z "${ACCOUNT_ID}" ]]; then
    printf '账号 ID 不能为空，请先选择 1 查看账号。\n' >&2
    return 1
  fi
  CURRENT_ACCOUNT_ID="${ACCOUNT_ID}"
}

read_positive_number() {
  local prompt="$1"
  local default_value="$2"
  local value
  read -r -p "${prompt}（默认 ${default_value}）: " value
  value="${value:-${default_value}}"
  if [[ ! "${value}" =~ ^[1-9][0-9]*$ ]]; then
    printf '%s 必须是正整数。\n' "${prompt}" >&2
    return 1
  fi
  NUMBER_VALUE="${value}"
}

configure_cookie() {
  if [[ ! -f "${COOKIE_FILE}" ]]; then
    install -m 0600 "${SCRIPT_DIR}/cookie.txt.example" "${COOKIE_FILE}"
  fi

  local editor="${EDITOR:-}"
  if [[ -z "${editor}" ]]; then
    if command -v nano >/dev/null 2>&1; then
      editor="nano"
    elif command -v vi >/dev/null 2>&1; then
      editor="vi"
    else
      printf '未找到 nano 或 vi，请手工编辑 %s\n' "${COOKIE_FILE}" >&2
      return 1
    fi
  fi
  "${editor}" "${COOKIE_FILE}"

  local account_name account_id
  read -r -p "输入已有账号 ID 进行更新，直接回车则创建新账号: " account_id
  if [[ -n "${account_id}" ]]; then
    "${SCRIPT_DIR}/set-cookie.sh" --id "${account_id}"
    CURRENT_ACCOUNT_ID="${account_id}"
  else
    read -r -p "新账号名称（默认 主号）: " account_name
    "${SCRIPT_DIR}/set-cookie.sh" "${account_name:-主号}"
  fi
}

case "${1:-}" in
  "") ;;
  -h|--help) usage; exit 0 ;;
  *) usage >&2; exit 1 ;;
esac

for command_name in curl sed mktemp cat rm install; do
  command -v "${command_name}" >/dev/null 2>&1 || die "缺少命令: ${command_name}"
done

if [[ -r "${ENV_FILE}" ]] || (( EUID == 0 )); then
  SUDO=()
else
  command -v sudo >/dev/null 2>&1 || die "无法读取 API Key：缺少 sudo"
  SUDO=(sudo)
fi

API_KEY="$("${SUDO[@]}" sed -n 's/^API_KEY=//p' "${ENV_FILE}")"
[[ -n "${API_KEY}" ]] || die "无法从 ${ENV_FILE} 读取 API Key"
trap cleanup EXIT

while true; do
  printf '\n%s\n' "========== iCloud HME 菜单 =========="
  printf '%s\n' \
    "1. 查看账号" \
    "2. 创建隐藏邮箱" \
    "3. 查看隐藏邮箱列表" \
    "4. 收取账号最近邮件" \
    "5. 收取指定隐藏邮箱的邮件" \
    "6. 配置或更新 Cookie" \
    "0. 退出"
  if [[ -n "${CURRENT_ACCOUNT_ID}" ]]; then
    printf '当前账号: %s\n' "${CURRENT_ACCOUNT_ID}"
  fi
  read -r -p "请选择: " choice
  choice="${choice%$'\r'}"

  case "${choice}" in
    1)
      api_call GET "/api/accounts" || true
      pause
      ;;
    2)
      if read_account_id; then
        read -r -p "邮箱标签（可留空）: " label
        api_call POST "/api/create" \
          --header "Content-Type: application/x-www-form-urlencoded" \
          --data-urlencode "account_id=${ACCOUNT_ID}" \
          --data-urlencode "label=${label}" || true
      fi
      pause
      ;;
    3)
      if read_account_id; then
        api_call GET "/api/aliases" --get \
          --data-urlencode "account_id=${ACCOUNT_ID}" || true
      fi
      pause
      ;;
    4)
      if read_account_id && read_positive_number "邮件数量" 10; then
        limit="${NUMBER_VALUE}"
        if read_positive_number "最近天数" 7; then
          api_call GET "/api/inbox" --get \
            --data-urlencode "account_id=${ACCOUNT_ID}" \
            --data-urlencode "limit=${limit}" \
            --data-urlencode "days=${NUMBER_VALUE}" || true
        fi
      fi
      pause
      ;;
    5)
      if read_account_id; then
        read -r -p "隐藏邮箱地址: " alias
        if [[ -z "${alias}" ]]; then
          printf '隐藏邮箱地址不能为空。\n' >&2
        elif read_positive_number "邮件数量" 10; then
          limit="${NUMBER_VALUE}"
          if read_positive_number "最近天数" 7; then
            api_call GET "/api/inbox" --get \
              --data-urlencode "account_id=${ACCOUNT_ID}" \
              --data-urlencode "alias=${alias}" \
              --data-urlencode "limit=${limit}" \
              --data-urlencode "days=${NUMBER_VALUE}" || true
          fi
        fi
      fi
      pause
      ;;
    6)
      configure_cookie || true
      pause
      ;;
    0)
      exit 0
      ;;
    *)
      printf '无效选项，请输入 0-6。\n' >&2
      ;;
  esac
done
