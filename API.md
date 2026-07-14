# iCloud Hide My Email API 文档

## API 鉴权

除 `/healthz` 外，所有 `/api/*` 请求必须携带部署时配置的 `API_KEY`：

```http
Authorization: Bearer <API_KEY>
```

也可以使用：

```http
X-API-Key: <API_KEY>
```

## 概述

HTTP JSON API，所有接口返回统一格式：

```json
{
  "success": true,
  "data": {},
  "message": ""
}
```

**错误响应:**
- `400 Bad Request` — 参数错误
- `401 Unauthorized` — 会话失效
- `404 Not Found` — 账号不存在
- `502 Bad Gateway` — iCloud 服务错误

---

## 核心接口

### 1. 创建 HME 别名

```http
POST /api/create
Content-Type: application/json

{
  "account_id": "acc_1",
  "label": "注册某网站"
}
```

该接口也接受 `application/x-www-form-urlencoded` 格式的 `account_id` 和 `label`，供交互脚本调用。

**响应:**
```json
{
  "success": true,
  "data": {
    "email": "xyz123@icloud.com",
    "label": "注册某网站",
    "created_at": "2024-01-15T10:30:00Z",
    "account_id": "acc_1"
  }
}
```

**参数说明:**
- `account_id` (必填) — 账号 ID
- `label` (可选) — 别名标签，默认为 "Created YYYY-MM-DD HH:mm"

**错误情况:**
- `401` — Cookie 过期，需更新
- `502` — iCloud 服务错误，会自动重试 5 次

---

### 2. 读取邮件

```http
GET /api/inbox?account_id=acc_1&alias=xyz123@icloud.com&limit=20&days=7
```

**响应 (走 IMAP,App Password):**
```json
{
  "success": true,
  "data": {
    "account_id": "acc_1",
    "alias": "xyz123@icloud.com",
    "count": 2,
    "method": "imap",
    "messages": [
      {
        "id": "1042",
        "from": "GitHub <noreply@github.com>",
        "to": "xyz123@icloud.com",
        "subject": "[GitHub] Please verify your email address",
        "date": "2026-07-09T14:32:10+08:00",
        "preview": "Almost done! To finish setting up your account, we just need to verify.."
      }
    ]
  }
}
```

**响应 (回退到 Web API,Cookie):** `method` 变为 `web_api`
```json
{
  "success": true,
  "data": {
    "account_id": "acc_1",
    "alias": "xyz123@icloud.com",
    "count": 1,
    "method": "web_api",
    "messages": [
      {
        "id": "AQMkAD...",
        "from": "GitHub <noreply@github.com>",
        "to": "xyz123@icloud.com",
        "subject": "[GitHub] Please verify your email address",
        "date": "Wed, 09 Jul 2026 06:32:10 GMT",
        "preview": "Almost done! To finish setting up your account.."
      }
    ]
  }
}
```

**参数说明:**
- `account_id` (必填) — 账号 ID
- `alias` (可选) — 只返回发到该别名的邮件;不传返回收件箱最近邮件
- `limit` (可选) — 返回邮件数量，默认 20
- `days` (可选) — 查找最近几天的邮件，默认 7 (仅 IMAP 模式)

**邮件读取双路径 (自动选择):**
1. **优先: IMAP (App Password)** — 设置了 App Password 时使用,支持服务端按收件人搜索
2. **回退: Web API (Cookie 认证)** — 无 App Password 或 IMAP 失败时,通过 iCloud mccgateway 端点读取

响应中 `"method": "imap"` 或 `"method": "web_api"` 标识实际使用的读取方式。

**别名过滤逻辑:**
- **IMAP (`FindByRecipient`):** 先用原生 IMAP `TO` 头搜索 (配合 `days` 时间范围);无结果时拉取最近 `limit*3` 条本地按 `To` 兜底过滤
- **Web API (`FindByAlias`):** iCloud Web API 不支持按收件人搜索,拉取 `limit*2` (至少 50) 条后本地对 `Subject`/`From`/`To` 做包含匹配

**返回字段差异 (两条路径):**
- `id` — IMAP 是 UID 数字串,Web API 是 iCloud GUID
- `date` — IMAP 走 RFC3339,Web API 是原始邮件头 RFC1123 串
- `preview` — 正文摘要,非完整正文

---

## 账号管理接口

### 3. 列出所有账号

```http
GET /api/accounts
```

**响应:**
```json
{
  "success": true,
  "data": [
    {
      "id": "acc_1",
      "name": "主号",
      "host": "imap.mail.me.com"
    }
  ]
}
```

**注意:** 响应中不包含敏感信息（cookies、app_passwords）

---

### 4. 添加账号

**简化版（cookies 可选）:**
```http
POST /api/accounts
Content-Type: application/json

{
  "name": "新账号",
  "host": "icloud.com",
  "proxy": "http://user:pass@host:port"
}
```

**完整版（包含 Cookie）:**
```http
POST /api/accounts
Content-Type: application/json

{
  "name": "新账号",
  "cookies": "{\"x-apple-session-token\":\"token_value\"}",
  "host": "icloud.com",
  "proxy": "http://user:pass@host:port"
}
```

**响应:**
```json
{
  "success": true,
  "data": {
    "id": "acc_3",
    "name": "新账号",
    "host": "icloud.com",
    "status": "pending"
  }
}
```

**参数说明:**
- `name` (必填) — 账号名称
- `cookies` (可选) — Cookie 字符串,支持两种格式:
  - JSON: `"{\"name\":\"value\"}"`
  - Header: `"name1=value1; name2=value2"`
- `host` (可选) — iCloud 域名,默认 `icloud.com`
- `proxy` (可选) — HTTP/SOCKS5 代理

**注意:** 不传 cookies 时,账号状态为 `pending`,需通过 `/login` 接口登录获取 Cookie

---

### Cookie 文件导入

用于脚本通过 multipart 表单导入完整 Cookie Header，避免 JSON 转义问题。首次创建传 `name`，更新已有账号传 `id`。

```http
POST /api/accounts/import-cookie
Authorization: Bearer <API_KEY>
Content-Type: multipart/form-data

cookies=<完整 Cookie Header>
name=主号
host=icloud.com
```

项目提供的 `deploy/set-cookie.sh` 已封装该接口。只有 Cookie 校验成功时才返回 2xx。

---

### 5. 账号密码登录（获取 Cookie）

```http
POST /api/accounts/:id/login
Content-Type: application/json

{
  "password": "用户的常规iCloud密码",
  "otp_code": "123456"  // 可选,2FA 验证码
}
```

**参数说明:**
- `:id` (路径参数) — 账号 ID
- `password` (必填) — iCloud 账号的常规密码(**不是** App Password)
- `otp_code` (可选) — 双重认证验证码

**响应:**
```json
{
  "success": true,
  "data": {
    "id": "acc_1",
    "cookies": {
      "x-apple-session-token": "...",
      "X-APPLE-WEBAUTH-TOKEN": "...",
      "X-APPLE-WEBAUTH-USER": "..."
    }
  }
}
```

**注意事项:**
- 密码是登录 appleid.apple.com 的**常规账号密码**,不是 App 专用密码
- 登录前账号必须已设置 `icloud_email` 字段
- 登录成功后 Cookie 会自动保存到 accounts.json
- 启用 2FA 时,第一次请求会被拒绝,需要带 `otp_code` 重试

---

### 6. 删除账号

```http
DELETE /api/accounts/:id
```


**响应:**
```json
{
  "success": true,
  "data": {
    "id": "acc_3"
  }
}
```

**错误情况:**
- `404` — 账号不存在

---

### 7. 设置 App Password

```http
POST /api/accounts/:id/password
Content-Type: application/json

{
  "icloud_email": "your_email@icloud.com",
  "app_password": "xxxx-xxxx-xxxx-xxxx"
}
```

**响应:**
```json
{
  "success": true,
  "data": {
    "id": "acc_1",
    "icloud_email": "your_email@icloud.com"
  }
}
```

**参数说明:**
- `icloud_email` (必填) — iCloud 邮箱地址
- `app_password` (必填) — App 专用密码

**用途:** App Password 用于 IMAP 邮件读取，生成方式见 [appleid.apple.com](https://appleid.apple.com)

---

## 别名管理接口

### 8. 列出所有别名

```http
GET /api/aliases?account_id=acc_1
```

**响应:**
```json
{
  "success": true,
  "data": {
    "account_id": "acc_1",
    "count": 15,
    "aliases": [
      {
        "email": "xyz123@icloud.com",
        "anonymousId": "abc123",
        "label": "注册某网站",
        "active": true,
        "createdAt": "2024-01-15T10:30:00Z"
      }
    ]
  }
}
```

**参数说明:**
- `account_id` (必填) — 账号 ID

**别名字段:**
- `email` — HME 邮箱地址
- `anonymousId` — 别名唯一标识（用于停用/激活/删除）
- `label` — 用户定义的标签
- `active` — 是否激活
- `createdAt` — 创建时间

---

### 9. 停用别名

```http
POST /api/aliases/:id/deactivate
Content-Type: application/json

{
  "account_id": "acc_1"
}
```

**响应:**
```json
{
  "success": true,
  "data": {
    "anonymous_id": "abc123",
    "success": true
  }
}
```

**参数说明:**
- `:id` (路径参数) — 别名的 `anonymousId`
- `account_id` (必填) — 账号 ID

**说明:** 停用后别名不再接收邮件，但可随时激活恢复

---

### 10. 激活别名

```http
POST /api/aliases/:id/reactivate
Content-Type: application/json

{
  "account_id": "acc_1"
}
```

**响应:**
```json
{
  "success": true,
  "data": {
    "anonymous_id": "abc123",
    "success": true
  }
}
```

**参数说明:**
- `:id` (路径参数) — 别名的 `anonymousId`
- `account_id` (必填) — 账号 ID

**说明:** 激活已停用的别名，恢复邮件接收

---

### 11. 删除别名

```http
DELETE /api/aliases/:id
Content-Type: application/json

{
  "account_id": "acc_1"
}
```

**响应:**
```json
{
  "success": true,
  "data": {
    "anonymous_id": "abc123"
  }
}
```

**参数说明:**
- `:id` (路径参数) — 别名的 `anonymousId`
- `account_id` (必填) — 账号 ID

**注意:** 删除不可恢复！如果直接删除失败，会先停用再删除

---

## 使用示例

### curl 示例

```bash
# 创建别名
curl -X POST http://localhost:8081/api/create \
  -H "Content-Type: application/json" \
  -d '{"account_id": "acc_1", "label": "GitHub"}'

# 读取邮件
curl "http://localhost:8081/api/inbox?account_id=acc_1&alias=xyz123@icloud.com&limit=10"

# 列出别名
curl "http://localhost:8081/api/aliases?account_id=acc_1"

# 停用别名
curl -X POST http://localhost:8081/api/aliases/abc123/deactivate \
  -H "Content-Type: application/json" \
  -d '{"account_id": "acc_1"}'

# 删除别名
curl -X DELETE http://localhost:8081/api/aliases/abc123 \
  -H "Content-Type: application/json" \
  -d '{"account_id": "acc_1"}'
```

### Python 示例

```python
import requests

BASE_URL = "http://localhost:8081/api"

# 创建别名
resp = requests.post(f"{BASE_URL}/create", json={
    "account_id": "acc_1",
    "label": "Netflix"
})
print(resp.json())

# 读取邮件
resp = requests.get(f"{BASE_URL}/inbox", params={
    "account_id": "acc_1",
    "alias": "xyz123@icloud.com",
    "limit": 10
})
print(resp.json())

# 列出别名
resp = requests.get(f"{BASE_URL}/aliases", params={"account_id": "acc_1"})
for alias in resp.json()["data"]["aliases"]:
    print(f"{alias['email']} - {alias['label']} (active: {alias['active']})")
```

---

## 认证说明

### Cookie 认证 (推荐,功能最完整)

用于：创建别名、列出别名、停用/激活/删除别名、**读取邮件**

**获取方式:**
1. 浏览器登录 [icloud.com](https://www.icloud.com) 或 [icloud.com.cn](https://www.icloud.com.cn) (国区)
2. F12 → Application → Cookies
3. 导出全部 Cookie 为 `{"key":"value"}` 格式 JSON

**关键 Cookie:**
- `X-APPLE-WEBAUTH-TOKEN` — 认证 token
- `X-APPLE-WEBAUTH-USER` — 含 dsid (`v=1:s=1:d=22789132008`)
- `X-APPLE-WEBAUTH-HSA-TRUST` — 设备信任 token
- `X-APPLE-DS-WEB-SESSION-TOKEN` — 会话 token

**有效期:** 约 24 小时

### App Password 认证 (IMAP 回退)

仅用于 Web API 失败时的邮件读取回退

**获取方式:**
1. 登录 [appleid.apple.com](https://appleid.apple.com)
2. 登录和安全 → App 专用密码
3. 生成新密码

---

## 技术说明

### 邮件读取实现

**Web API 路径** (`internal/mail/web_client.go`):
1. 调用 `setup.icloud.com.cn/setup/ws/1/validate` 获取 `mccgateway` URL
2. 调用 `mccgateway/mailws2/v1/thread/search` 读取邮件

**⚠️ 已知坑:**
- `validate` 返回的 mccgateway URL 可能带 `:443` 端口 (如 `p217-mccgateway.icloud.com.cn:443`)
- tls-client 的 cookie jar 按不带端口的 host 存储 cookie
- 带端口请求时 cookie 无法附加,导致 403
- **解决:** 解析 URL 后剥离端口号

**clientBuildNumber:** 与浏览器一致,当前 `2624Build22`

**IMAP 路径** (`internal/mail/client.go`):
- 标准 IMAP 协议,连接 `imap.mail.me.com:993`
- 需要 App Password

---

## 错误处理

### 会话失效 (401)

```json
{
  "success": false,
  "message": "iCloud 会话失效，请更新 Cookie: HTTP 401"
}
```

**解决:** 更新 `accounts.json` 中的 Cookie

### iCloud 服务错误 (502)

```json
{
  "success": false,
  "message": "创建邮箱失败: HTTP 429"
}
```

**说明:** 429 错误会自动重试最多 5 次

### 参数错误 (400)

```json
{
  "success": false,
  "message": "参数错误: account_id 必填"
}
```

---

## 限制

- **创建频率**: iCloud 限制别名创建频率，过快会返回 429
- **Cookie 有效期**: 约 24 小时，需定期更新
- **邮件读取**: 依赖 IMAP 连接，超时默认 30 秒
