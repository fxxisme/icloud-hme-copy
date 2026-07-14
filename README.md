# iCloud Hide My Email 本地管理工具

[English](#english) | 中文

通过逆向 iCloud Web 接口和 IMAP 邮件协议，实现 Apple iCloud 隐藏邮箱别名的创建、列出和邮件收取功能。

## 功能特性

- ✅ **创建 HME 别名** — 自动生成 iCloud 隐藏邮箱地址
- ✅ **列出所有别名** — 查看账号下的所有 HME 别名
- ✅ **收取邮件** — 通过 IMAP 或 Web API 读取发到 HME 别名的邮件
- ✅ **双路径读信** — 邮件读取优先走 IMAP (App Password),无 App Password 时回退 Web API (Cookie)
- ✅ **多账号管理** — 支持多个 iCloud 账号并行管理
- ✅ **双认证模式** — Cookie (创建别名 + 读邮件回退) 和 App Password (IMAP 优先)

## 快速开始

### 运行前：配置 API 鉴权

服务必须通过环境变量配置 `API_KEY`。如果 `API_KEY` 为空或未设置，程序会直接拒绝启动。

```bash
# 生成一个随机密钥，供当前终端中的本地服务使用
export API_KEY="$(openssl rand -hex 32)"

# 启动服务
./icloud-hme
```

除健康检查 `/healthz` 外，所有 `/api/*` 请求都必须携带相同的密钥。推荐使用 Bearer Token：

```bash
curl http://127.0.0.1:8081/api/accounts \
  -H "Authorization: Bearer $API_KEY"
```

也支持通过 `X-API-Key` 请求头传递：

```bash
curl http://127.0.0.1:8081/api/accounts \
  -H "X-API-Key: $API_KEY"
```

请妥善保管密钥，不要将真实密钥提交到 Git。公网部署必须使用 HTTPS，否则 API 密钥、iCloud 密码和 Cookie 都可能以明文传输。

### 推荐：Linux 二进制 + systemd

单服务器部署推荐 SSH 登录服务器后拉取代码，通过安装脚本编译 Linux 二进制并交给 systemd 托管，可获得开机自启、异常重启和统一日志管理。脚本当前支持 `x86_64`，服务器需安装 Git、OpenSSL、curl、tar、sha256sum 和 systemd。从 Docker 迁移时，先在原项目目录执行 `docker compose down`，避免占用 8081 端口。

```bash
# 在 x86_64 服务器执行
git clone https://github.com/fxxisme/icloud-hme-copy.git
cd icloud-hme-copy
bash deploy/install.sh
```

如果系统未安装 Go 或版本低于 `1.26`，脚本会通过 Go 官方下载服务获取最新稳定版，校验 SHA256 后安装到 `/usr/local/go`；已有合格版本不会被修改。随后脚本会创建低权限用户，并将运行文件集中到 `/opt/icloud-hme`：

```text
/opt/icloud-hme/
├── bin/icloud-hme
├── data/accounts.json
└── config/icloud-hme.env
```

系统外部只会安装 `/etc/systemd/system/icloud-hme.service`。如果存在旧版部署目录 `/var/lib/icloud-hme`、`/etc/icloud-hme`，或仓库内已有 `data/accounts.json`，首次安装时会自动迁移。重复运行安装脚本会更新程序，并保留现有数据和 API Key。

配置 Cookie 时不需要手写 JSON。复制示例文件，只在 `cookie.txt` 中粘贴浏览器请求头里的完整 Cookie，然后运行脚本：

```bash
cp deploy/cookie.txt.example deploy/cookie.txt
nano deploy/cookie.txt
./deploy/set-cookie.sh             # 创建账号并自动命名
```

账号名称会自动取 `real_email` 的 `@` 前缀。同一 `real_email` 再次创建时，本次导入的账号会保留，旧的重复账号会自动删除；旧账号 ID、App Password 等附加配置也会随之删除。

Cookie 失效后，通过账号 ID 更新：

```bash
nano deploy/cookie.txt
./deploy/set-cookie.sh --id acc_xxxxxxxx
```

`deploy/cookie.txt` 已被 Git 忽略并限制为 `0600` 权限；导入成功后脚本会自动清空，失败时保留内容供排查。

日常操作可以直接运行交互菜单，不需要手写 curl：

```bash
./deploy/menu.sh
```

菜单支持查看账号、创建隐藏邮箱、查看别名、收取最近邮件、按隐藏邮箱筛选邮件，以及配置或更新 Cookie。有 `jq` 时响应会自动美化，没有 `jq` 也可正常使用。

systemd 服务默认监听 `0.0.0.0:8081`，部署后可以直接通过服务器 IP 测试。项目本身不提供 TLS，公网使用时必须通过防火墙限制 8081 端口来源，或改为监听 `127.0.0.1:8081` 并通过 Nginx/Caddy 提供 HTTPS。查看日志和健康状态：

```bash
sudo journalctl -u icloud-hme -f
curl http://127.0.0.1:8081/healthz
```

升级只需拉取代码并重新执行安装脚本：

```bash
git pull
bash deploy/install.sh
```

卸载默认保留账号数据和 API Key；需要彻底删除时使用 `--purge`：

```bash
bash deploy/uninstall.sh
bash deploy/uninstall.sh --purge
```

### 可选：Docker Compose 部署

需要容器隔离或统一镜像发布时可以使用 Docker。低配置服务器首次执行 `--build` 可能较慢；生产环境更适合由本地或 CI 构建并推送镜像，服务器只拉取并启动。

```bash
# 从示例创建配置文件
cp .env.example .env

# 生成密钥并写入 .env（Linux）
API_KEY="$(openssl rand -hex 32)"
sed -i "s/^API_KEY=.*/API_KEY=${API_KEY}/" .env

# 非 root 容器需要数据目录属于 UID/GID 10001
sudo install -d -m 700 -o 10001 -g 10001 data

docker compose up -d --build
docker compose ps
```

Compose 会自动读取项目根目录的 `.env`。其中：

- `API_KEY`：必填，API 鉴权密钥
- `BIND_ADDRESS`：宿主机监听地址，默认 `0.0.0.0`
- `HOST_PORT`：宿主机端口，默认 `8081`

```bash
# 查看运行状态和日志
docker compose ps
docker compose logs -f icloud-hme
```

Compose 默认将服务发布到 `0.0.0.0:8081`。项目本身不提供 TLS，公网部署必须通过防火墙限制来源，或使用 Nginx/Caddy 提供 HTTPS。通过反向代理部署时，建议将 `BIND_ADDRESS` 改为 `127.0.0.1`。

### 1. 安装

```bash
# 前置要求: Go 1.26+
go version  # 确认 Go 版本

# 克隆项目
git clone https://github.com/fxxisme/icloud-hme-copy.git
cd icloud-hme-copy

# 编译
go build -o icloud-hme .
```

### 2. 配置账号

服务运行后推荐通过 Cookie 导入脚本配置账号：

```bash
cp deploy/cookie.txt.example deploy/cookie.txt
nano deploy/cookie.txt
./deploy/set-cookie.sh
```

程序会自动校验并持久化账号。`accounts.json.template` 仅用于了解当前存储结构，不建议在服务运行时直接编辑数据文件。

### 3. 启动服务

```bash
API_KEY="replace-with-a-random-secret" ./icloud-hme

# 服务默认监听 :8081
# 使用命令行参数修改监听端口
API_KEY="replace-with-a-random-secret" ./icloud-hme -addr :9090
```

## API 接口

### 核心接口

#### 创建 HME 别名

```bash
POST /api/create

# 请求体
{
  "account_id": "acc_1",      # 必填: 账号 ID
  "label": "注册某网站"        # 可选: 别名标签
}

# 响应
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

#### 读取邮件

```bash
GET /api/inbox?account_id=acc_1&alias=xyz123@icloud.com&limit=20&days=7

# 参数说明:
#   account_id - 必填: 账号 ID
#   alias      - 可选: 只读取发到该别名的邮件
#   limit      - 可选: 返回邮件数量 (默认 20)
#   days       - 可选: 查找最近几天的邮件 (默认 7,仅 IMAP 模式)

# 响应
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
        "from": "noreply@example.com",
        "to": "xyz123@icloud.com",
        "subject": "欢迎注册",
        "preview": "感谢您的注册...",
        "date": "2026-07-09T14:32:10+08:00"
      }
    ]
  }
}

# 读取方式 (自动选择):
#   method: "imap"    — 通过 App Password 认证 (优先)
#   method: "web_api" — 通过 Cookie 认证,无需 App Password (回退)
```

### 账号管理接口

#### 列出所有账号

```bash
GET /api/accounts

# 响应
{
  "success": true,
  "data": [
    {"id": "acc_1", "name": "主号"},
    {"id": "acc_2", "name": "副号"}
  ]
}
```

#### 添加账号

**简化版（cookies 可选）:**

```bash
POST /api/accounts

# 请求体
{
  "name": "新账号",
  "host": "icloud.com",           # 可选
  "proxy": "http://..."           # 可选
}

# 响应 - 状态为 pending,需登录
{
  "success": true,
  "data": {
    "id": "acc_xxx",
    "name": "新账号",
    "status": "pending"
  }
}
```

**完整版（带 Cookie）:**

```bash
POST /api/accounts

# 请求体
{
  "name": "新账号",
  "cookies": "{\"x-apple-session-token\":\"token_value\"}",  # JSON 或 Header 格式
  "host": "icloud.com",           # 可选
  "proxy": "http://..."           # 可选
}

# 响应
{
  "success": true,
  "data": {
    "id": "acc_3",
    "name": "新账号",
    "status": "active"
  }
}
```

#### 账号登录（获取 Cookie）

```bash
POST /api/accounts/:id/login

# 请求体
{
  "password": "用户的常规iCloud密码",  # 不是 App Password
  "otp_code": "123456"                  # 可选,2FA 验证码
}

# 响应
{
  "success": true,
  "data": {
    "id": "acc_1",
    "cookies": {
      "x-apple-session-token": "...",
      "X-APPLE-WEBAUTH-TOKEN": "..."
    }
  }
}
```

#### 删除账号

```bash
DELETE /api/accounts/:id

# 响应
{
  "success": true,
  "data": {"id": "acc_3"}
}
```

#### 设置 App Password

```bash
POST /api/accounts/:id/password

# 请求体
{
  "icloud_email": "your_email@icloud.com",
  "app_password": "xxxx-xxxx-xxxx-xxxx"
}

# 响应
{
  "success": true,
  "data": {
    "id": "acc_1",
    "icloud_email": "your_email@icloud.com"
  }
}
```

### 别名管理接口

#### 列出所有别名

```bash
GET /api/aliases?account_id=acc_1

# 响应
{
  "success": true,
  "data": {
    "account_id": "acc_1",
    "count": 15,
    "aliases": [
      {
        "email": "xyz123@icloud.com",
        "label": "注册某网站",
        "created_at": "2024-01-15T10:30:00Z"
      }
    ]
  }
}
```

#### 停用别名

```bash
POST /api/aliases/:id/deactivate

# 请求体
{
  "account_id": "acc_1"
}

# 响应
{
  "success": true,
  "data": {
    "anonymous_id": "abc123",
    "success": true
  }
}
```

#### 激活别名

```bash
POST /api/aliases/:id/reactivate

# 请求体
{
  "account_id": "acc_1"
}

# 响应
{
  "success": true,
  "data": {
    "anonymous_id": "abc123",
    "success": true
  }
}
```

#### 删除别名

```bash
DELETE /api/aliases/:id

# 请求体
{
  "account_id": "acc_1"
}

# 响应
{
  "success": true,
  "data": {
    "anonymous_id": "abc123"
  }
}
```

## 认证方式

### 方式一: Cookie 认证 (推荐,功能最完整)

Cookie 认证可实现所有功能:创建别名、读取邮件、管理别名。

**适用范围:**
- 创建/停用/激活/删除 HME 别名 ✅
- 读取邮件 (通过 iCloud Web API,无需 App Password) ✅

**获取 Cookie:**

1. 使用浏览器登录 [icloud.com](https://www.icloud.com) 或 [icloud.com.cn](https://www.icloud.com.cn) (国区)
2. 打开浏览器开发者工具 (F12)
3. 进入 Application → Cookies
4. 导出全部 Cookie 为 `{"key":"value"}` 格式的 JSON

**关键 Cookie (必需):**
- `X-APPLE-WEBAUTH-TOKEN` — 认证 token
- `X-APPLE-WEBAUTH-USER` — 含 dsid (`v=1:s=1:d=22789132008`)
- `X-APPLE-WEBAUTH-HSA-TRUST` — 设备信任 token
- `X-APPLE-DS-WEB-SESSION-TOKEN` — 会话 token

**注意:** 导出的 Cookie 值不要包含多余的引号或转义字符。

### 方式二: App Password 认证 (IMAP,优先读邮件)

App Password 用于 IMAP 读取邮件,是邮件读取的优先路径 (支持服务端按收件人搜索)。

**生成 App Password:**

1. 登录 [appleid.apple.com](https://appleid.apple.com)
2. 进入 "登录和安全" → "App 专用密码"
3. 生成新密码,用于此工具

### 邮件读取双路径

`GET /api/inbox` 自动选择读取方式:

1. **优先: IMAP (App Password)** — 设置了 App Password 时使用,支持服务端按收件人 (`TO`) 搜索
2. **回退: Web API (Cookie)** — 无 App Password 或 IMAP 失败时,通过 `mccgateway` 端点读取,本地按别名过滤

响应中包含 `"method": "web_api"` 或 `"method": "imap"` 字段,标识实际使用的读取方式。

## 项目架构

```
icloud-hme/
├── main.go                 # 入口: 加载配置、初始化管理器、启动服务
├── accounts.json           # 账号配置文件 (自动生成)
├── go.mod
└── internal/
    ├── account/
    │   └── manager.go      # 多账号管理器 (持久化、客户端工厂)
    ├── hme/
    │   ├── client.go       # iCloud HME Web 客户端 (Cookie 认证)
    │   └── auth.go         # SRP 登录 (账号密码 + 2FA 获取 Cookie)
    ├── mail/
    │   ├── client.go       # IMAP 邮件客户端 (App Password 认证)
    │   └── web_client.go   # Web 邮件客户端 (Cookie 认证,无需 App Password)
    └── server/
        └── server.go       # HTTP API (Gin 路由 + 请求处理)
```

### 核心模块

- **account.Manager**: 管理多个 iCloud 账号,负责配置持久化和客户端创建
- **hme.Client**: 封装 iCloud HME Web API,支持 Cookie 认证
- **hme.auth**: SRP 协议登录,支持账号密码 + 可选 2FA
- **mail.Client**: IMAP 邮件客户端 (App Password,优先读邮件)
- **mail.WebClient**: 通过 iCloud Web API (mccgateway) 读取邮件,无需 App Password
- **server.Server**: HTTP API 服务,提供 RESTful 接口

## 技术栈

- **Go 1.26+**
- **Gin** — HTTP 框架
- **go-imap** — IMAP 协议实现
- **tls-client** — TLS 指纹模拟 (绕过 iCloud 反爬)

## 常见问题

### Q: 创建别名返回 401/403 错误?

**A:** Cookie 已过期，需要重新获取。iCloud Cookie 有效期通常为 24 小时。

### Q: 读取邮件返回超时?

**A:** 检查网络连接，确保可以访问 `imap.mail.me.com:993`。

### Q: 如何查看某个别名收到了哪些邮件?

**A:** 调用 `GET /api/inbox?account_id=acc_1&alias=your_alias@icloud.com`

### Q: 支持同时管理多个 iCloud 账号吗?

**A:** 支持，在 `accounts.json` 中配置多个账号即可，每个账号有独立的 `id`。

## 开发指南

### 本地开发

```bash
# 安装依赖
go mod download

# 运行（API_KEY 必填；开发模式会输出更详细的日志）
API_KEY="replace-with-a-random-secret" go run . -debug

# 编译
go build -o icloud-hme .

# 交叉编译 (Linux)
GOOS=linux GOARCH=amd64 go build -o icloud-hme .
```

### 代码规范

- 代码注释使用中文
- 错误信息返回给用户时使用中文
- API 响应格式统一: `{success: bool, data: any, message: string}`

## 许可证

MIT License

---
## 社区

友情链接：[LINUX DO](https://linux.do)

## English

A local management tool for Apple iCloud Hide My Email (HME) aliases, supporting creation, listing, and email reading through reverse-engineered iCloud Web API and IMAP protocol.

### Features

- Create HME aliases automatically
- List all aliases for an account
- Read emails sent to HME aliases via IMAP
- Manage multiple iCloud accounts
- Dual authentication: Cookie and App Password

### Quick Start

`API_KEY` is required. The service refuses to start when it is empty or missing. Except for `/healthz`, every `/api/*` request must use either `Authorization: Bearer <API_KEY>` or `X-API-Key: <API_KEY>`.

```bash
# Build and run locally
go build -o icloud-hme .
export API_KEY="$(openssl rand -hex 32)"
./icloud-hme

# Call an authenticated endpoint
curl http://127.0.0.1:8081/api/accounts \
  -H "Authorization: Bearer $API_KEY"
```

For a single x86_64 Linux server, the recommended deployment is a Linux binary managed by systemd. SSH into the server, clone the repository, and run the installer. If Go 1.26+ is unavailable, the script uses the official Go download service to fetch the latest stable release, verifies its SHA256 checksum, and installs it under `/usr/local/go`. Runtime files are kept under `/opt/icloud-hme`; only the systemd unit is installed outside that directory. Existing API keys and account data are preserved when the installer is run again.

```bash
git clone https://github.com/fxxisme/icloud-hme-copy.git
cd icloud-hme-copy
bash deploy/install.sh

# Paste a complete Cookie request header into this file, then import it
cp deploy/cookie.txt.example deploy/cookie.txt
nano deploy/cookie.txt
./deploy/set-cookie.sh

# Interactive account, alias, and inbox operations
./deploy/menu.sh

# Keep data and configuration
bash deploy/uninstall.sh

# Remove everything, including data and the API key
bash deploy/uninstall.sh --purge
```

Docker Compose is also supported when container isolation or image-based releases are preferred:

```bash
cp .env.example .env
API_KEY="$(openssl rand -hex 32)"
sed -i "s/^API_KEY=.*/API_KEY=${API_KEY}/" .env
sudo install -d -m 700 -o 10001 -g 10001 data
docker compose up -d --build
```

Compose publishes port `8081` by default. Use HTTPS through a reverse proxy when exposing the service publicly, because API requests may contain iCloud passwords and cookies.

See [API Documentation](#api-接口) for detailed usage.
