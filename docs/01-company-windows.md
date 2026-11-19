# 01 · 公司 Windows 电脑部署（常开服务器）

目标：把公司这台常开的 Windows 电脑变成 Obsidian 同步服务器，**不装 Docker、默认不需要管理员**。

---

## 1. 前置条件

| 项目 | 要求 | 说明 |
|---|---|---|
| 系统 | Windows 10 1803+ / Windows 11 | 需要自带 `curl.exe`、`tar.exe` |
| 架构 | x64（amd64） | ARM64 会以模拟方式运行 amd64 版本 |
| PowerShell | 5.1+ | 系统自带 |
| 磁盘 | ≥ 2 GB 空闲 | 47 MB 程序 + 数据 + 备份 |
| 网络 | 能访问 GitHub（或镜像） | 国内可用 `-Mirror ghproxy` |
| 权限 | 普通用户即可 | 防火墙规则 / Tailscale 安装需要管理员 |

> 公司电脑如果有软件白名单/域策略，先确认允许运行第三方可执行文件与后台计划任务。

---

## 2. 安装

```powershell
git clone https://github.com/Kanyoh/obsidian-fns-deploy.git
cd obsidian-fns-deploy\scripts\windows
powershell -ExecutionPolicy Bypass -File .\install.ps1
```

脚本动作：

1. 下载 `fast-note-sync-service-3.6.1-windows-amd64.tar.gz`（GitHub 失败自动切 `gh-proxy.com`）；
2. 解压到 `%LOCALAPPDATA%\FNS`；
3. 用发布包自带的 `config.yaml` 生成配置：
   - `server.http-port` 改成你指定的端口；
   - `security.auth-token-key` 换成 32 字节随机值；
   - 日志级别改为 `info`；
4. 复制 `manage.ps1` 到安装目录；
5. 创建登录自启计划任务 `FNS-ObsidianSync`；
6. 启动服务并请求 `http://127.0.0.1:<port>/` 自检。

### 常用参数

| 参数 | 默认 | 作用 |
|---|---|---|
| `-Port` | `9000` | 服务端口 |
| `-InstallDir` | `%LOCALAPPDATA%\FNS` | 安装目录（可放 D 盘） |
| `-Version` | `3.6.1` | 服务端版本 |
| `-Mirror` | `auto` | `auto` / `github` / `ghproxy` |
| `-LocalArchive` | 空 | 用本地 tar.gz 离线安装 |
| `-SkipFirewall` | 关 | 不添加防火墙规则 |
| `-NoTask` | 关 | 不创建自启任务 |
| `-NoStart` | 关 | 安装完不启动 |
| `-Tailscale` | 关 | 安装后尝试 `tailscale serve` 输出 HTTPS 地址 |

示例：

```powershell
# 放 D 盘、端口 9100、离线安装
.\install.ps1 -Port 9100 -InstallDir "D:\FNS" -LocalArchive "D:\fast-note-sync-service-3.6.1-windows-amd64.tar.gz"

# 需要局域网直连（会提示管理员）
.\install.ps1 -Port 9000

# 只装、不启动、不建任务（自己控制）
.\install.ps1 -NoStart -NoTask -SkipFirewall
```

---

## 3. 让它真正"常开"

公司电脑常见三个坑：**睡眠、注销、省电策略**。

### 3.1 关闭睡眠（当前电源计划）

```powershell
powercfg /change standby-timeout-ac 0
powercfg /change hibernate-timeout-ac 0
powercfg /change monitor-timeout-ac 15
```

> 笔记本还要在「电源选项 → 合盖时」设为"不采取任何操作"，否则合盖就断。
> 公司策略可能锁死这些设置，必要时找 IT。

### 3.2 开机自启的三种级别

| 方式 | 需要管理员 | 触发条件 | 适用 |
|---|---|---|---|
| **登录时任务**（默认） | 否 | 用户登录后 | 电脑常登录、屏幕锁定但会话在 |
| **开机任务（最高权限）** | 是 | 开机即运行，无需登录 | 会重启、无人登录 |
| **Windows 服务（NSSM）** | 是 | 开机即运行 | 最稳，但需装 NSSM |

默认的登录任务在「计划任务 → FNS-ObsidianSync」可见。
如果电脑会重启且没人登录，用管理员 PowerShell 改成开机任务：

```powershell
schtasks /Delete /TN "FNS-ObsidianSync" /F
schtasks /Create /SC ONSTART /RU "SYSTEM" /RL HIGHEST /TN "FNS-ObsidianSync" `
  /TR "powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$env:LOCALAPPDATA\FNS\manage.ps1`" start" /F
```

> 注意：`-RU SYSTEM` 时 `%LOCALAPPDATA%` 不是你的用户目录，请把路径写成绝对路径
> （例如 `C:\Users\你的用户名\AppData\Local\FNS`）。

### 3.3 公司电脑被锁屏/切换用户

- 锁屏不影响登录会话里的进程，服务继续跑；
- **注销 / 关机 / 切换用户**会停掉登录任务，需要在步骤 3.2 改成开机任务或服务。

---

## 4. 防火墙与端口

- 只在**局域网直连**时需要放行端口；
- 用 Tailscale 时走 `tailscale serve` 代理到 `127.0.0.1`，**不需要**开防火墙；
- 管理员执行：

```powershell
netsh advfirewall firewall add rule name="FNS Obsidian Sync" dir=in action=allow protocol=TCP localport=9000
```

检查端口监听：

```powershell
Get-NetTCPConnection -LocalPort 9000 -State Listen
```

---

## 5. 初始化与自检

1. 浏览器打开 `http://127.0.0.1:9000` → 注册账号；
2. 「笔记库」→「复制 API 配置」；
3. 关闭注册（编辑 `config\config.yaml` 的 `user.register-is-enable: false` 后 `manage.ps1 restart`）；
4. 检查：

```powershell
powershell -File "$env:LOCALAPPDATA\FNS\manage.ps1" status
# process: pid=...  http: OK 200
```

---

## 6. 数据、日志、备份

| 内容 | 路径 |
|---|---|
| 配置 | `%LOCALAPPDATA%\FNS\config\config.yaml` |
| 数据 | `%LOCALAPPDATA%\FNS\storage\`（`database\db.sqlite3`、`uploads\`） |
| 日志 | `%LOCALAPPDATA%\FNS\logs\stdout.log`、`storage\logs\log.log` |
| 备份 | `%LOCALAPPDATA%\FNS\backups\` |

```powershell
powershell -File "$env:LOCALAPPDATA\FNS\manage.ps1" backup
```

> 备份会先停服务、打包 `config` + `storage`、再启动，避免 SQLite 写一半。
> 保留最近 7 份。详见 `04-backup-update.md`。

---

## 7. 卸载

```powershell
powershell -File "$env:LOCALAPPDATA\FNS\manage.ps1" uninstall
# 保留数据：manage.ps1 uninstall -KeepFiles
```

会停止进程、删除计划任务；默认连目录一起删（**先备份**）。

---

## 8. 公司环境注意事项

- **不要**把 `config.yaml`（含 auth key）或 `storage/` 提交到 Git；
- 公司代理如果做 HTTPS 中间人，可能影响插件连接——用 Tailscale 可绕过代理；
- 公司安全软件可能拦截"计划任务 + 后台进程"，遇到就找 IT 加白名单；
- 端口别用 80/443（可能被公司 IIS/网关占用），默认 9000 即可。
