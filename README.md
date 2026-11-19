# Obsidian 多端同步 · 便携部署套件（Fast Note Sync）

[![validate](https://github.com/Kanyoh/obsidian-fns-deploy/actions/workflows/validate.yml/badge.svg)](https://github.com/Kanyoh/obsidian-fns-deploy/actions/workflows/validate.yml)

> 只想快速上手？看 **一页纸操作卡**：[`docs/00-quick-card.md`](docs/00-quick-card.md)
> （公司电脑 + Tailscale，10 分钟全流程）

一套**在任意 Windows 电脑上 5 分钟跑起来**的 Obsidian 同步服务端部署脚本 + 文档。

适用场景：

- **公司电脑常开**，当作同步服务器；
- 家里 PC、平板、手机**不在同一网络**，也要读写同一份笔记；
- 不想装 Docker、不想买 VPS、不想把笔记放第三方云。

```
公司电脑（常开，跑 FNS 服务端）         家里 / 外出
┌──────────────────────────┐        ┌──────────────────┐
│ fast-note-sync-service   │◀──────▶│ 家里 PC + 平板    │
│ 端口 9000 / 数据本地      │ Tailscale│ 手机 Obsidian     │
└──────────────────────────┘  加密隧道 └──────────────────┘
                 ▲
                 │ 同一 tailnet（推荐）
```

> 服务端用开源项目 [Fast Note Sync Service](https://github.com/haierkeys/fast-note-sync-service)，
> 客户端用 Obsidian 插件 [Fast Note Sync](https://github.com/haierkeys/obsidian-fast-note-sync)（v2.4.0，支持移动端）。

---

## 5 分钟部署（公司 Windows 电脑）

### 1. 拿到本仓库

```powershell
git clone https://github.com/Kanyoh/obsidian-fns-deploy.git
cd obsidian-fns-deploy\scripts\windows
```

或直接在 GitHub 页面 **Code → Download ZIP** 解压。

### 2. 一键安装（无需管理员）

```powershell
powershell -ExecutionPolicy Bypass -File .\install.ps1
```

脚本会：

- 下载官方 Windows 版 `fast-note-sync-service`（约 47 MB，支持国内镜像）；
- 解压到 `%LOCALAPPDATA%\FNS`；
- 生成随机 `auth-token-key`、写入你指定的端口（默认 9000）；
- 注册"登录时自动启动"的计划任务（`FNS-ObsidianSync`）；
- 启动服务并打印本机 / 局域网地址。

常用参数：

```powershell
# 换端口、换目录、跳过防火墙
.\install.ps1 -Port 9000 -InstallDir "D:\FNS" -SkipFirewall

# 已手动下载 tar.gz，离线安装
.\install.ps1 -LocalArchive "D:\downloads\fast-note-sync-service-3.6.1-windows-amd64.tar.gz"

# 顺带配置 Tailscale 并开启 HTTPS（需先装好 Tailscale）
.\install.ps1 -Tailscale
```

### 3. 初始化账号

1. 浏览器打开 `http://127.0.0.1:9000`（或安装脚本打印的局域网地址）；
2. 首次访问注册账号（用户名例如 `Wink`，**新强密码**）；
3. 左侧「笔记库 / Vaults」→「复制 API 配置」（Copy API Config），得到：
   ```json
   { "api": "http://127.0.0.1:9000", "apiToken": "fns_xxx", "vault": "main" }
   ```
4. 回到服务端设置，**关闭注册**（`user.register-is-enable: false`），改完重启。

### 4. 配置 Obsidian 客户端

每台设备：

1. Obsidian ≥ 1.8.7，安装社区插件 **Fast Note Sync**（商店搜索，或手动放 `.obsidian/plugins/fast-note-sync/` 三件套）；
2. 插件设置 →「粘贴服务端授权配置」→ 粘贴上面 JSON；
3. 「客户端名称」分别写 `PC-公司` / `PC-家里` / `iPad` / `手机`；
4. 首次同步顺序：**公司 PC 先上传 → 家里 PC 空库下载 → 平板/手机最后接入**；
5. 建议先关闭「配置项同步」，稳定后再开（见 `docs/02-clients.md`）。

### 5. 不在公司时怎么连（关键）

公司网络通常没有公网 IP，也不允许端口映射。**推荐 Tailscale**：

1. 公司电脑、家里 PC、平板、手机都安装 [Tailscale](https://tailscale.com/download)，登录**同一账号**；
2. 公司电脑执行：
   ```powershell
   tailscale up
   tailscale serve --bg 9000
   ```
   会得到一个 `https://<机器名>.<tailnet>.ts.net` 的 HTTPS 地址；
3. 把每台设备插件的「远端服务地址」改成这个 `https://...` 地址（或 `http://100.x.y.z:9000`）。

这样不需要公网 IP、不需要路由器端口映射，流量走 WireGuard 加密隧道。

> 详细方案（含 Cloudflare Tunnel 备选、防火墙、ACL）见
> [`docs/03-remote-access-tailscale.md`](docs/03-remote-access-tailscale.md)。

---

## 仓库结构

```
obsidian-fns-deploy/
├── scripts/
│   ├── windows/
│   │   ├── install.ps1        # 一键安装（便携、免管理员）
│   │   └── manage.ps1         # start/stop/status/backup/update/logs/uninstall
│   └── linux/
│       └── install.sh         # Linux systemd 一键安装（可选）
├── deploy/
│   ├── docker-compose.yml     # Docker 部署（NAS / VPS）
│   ├── Caddyfile              # 自动 HTTPS 反代
│   └── nginx-fns.conf         # Nginx 反代（含 WebSocket）
└── docs/
    ├── 01-company-windows.md  # 公司电脑部署细节（常开、自启、省电、权限）
    ├── 02-clients.md          # PC / 平板 / 手机客户端配置与首同步
    ├── 03-remote-access-tailscale.md  # 跨网络访问三种方案
    ├── 04-backup-update.md    # 备份、升级、换机迁移
    └── 05-troubleshooting.md  # 常见故障排查
```

## 管理命令

安装后的目录里带有 `manage.ps1`：

```powershell
powershell -File "$env:LOCALAPPDATA\FNS\manage.ps1" status
powershell -File "$env:LOCALAPPDATA\FNS\manage.ps1" stop
powershell -File "$env:LOCALAPPDATA\FNS\manage.ps1" start
powershell -File "$env:LOCALAPPDATA\FNS\manage.ps1" backup
powershell -File "$env:LOCALAPPDATA\FNS\manage.ps1" update -Version 3.6.1
powershell -File "$env:LOCALAPPDATA\FNS\manage.ps1" logs
powershell -File "$env:LOCALAPPDATA\FNS\manage.ps1" open
```

## 数据在哪

| 内容 | 路径 |
|---|---|
| 程序 | `%LOCALAPPDATA%\FNS\fast-note-sync-service.exe` |
| 配置 | `%LOCALAPPDATA%\FNS\config\config.yaml` |
| 笔记/附件/数据库 | `%LOCALAPPDATA%\FNS\storage\` |
| 备份 | `%LOCALAPPDATA%\FNS\backups\` |
| 日志 | `%LOCALAPPDATA%\FNS\logs\` 与 `storage\logs\` |

> 备份只需要 `config\` + `storage\` 两个目录；`manage.ps1 backup` 会自动打包并保留最近 7 份。

## 安全

- 首次安装会生成随机 `auth-token-key`，不要把它提交到 Git；
- 公网暴露时务必 HTTPS（Tailscale 自带，或 Caddy/Cloudflare Tunnel）；
- 注册完账号后关闭注册；
- 定期备份 `storage/`；
- 本套件只负责部署，不收集任何数据。

## 版本

- 服务端：Fast Note Sync Service **3.6.1**
- 插件：Fast Note Sync **2.4.0**（Obsidian ≥ 1.8.7）
- 脚本依赖：Windows 10/11 自带 `curl.exe`、`tar.exe`、PowerShell 5.1

## License

MIT（脚本与文档）；上游服务端与插件遵循其各自许可证（GPL-3.0）。
