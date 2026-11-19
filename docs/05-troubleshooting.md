# 05 · 故障排查

先看日志：

```powershell
# 服务进程输出
Get-Content "$env:LOCALAPPDATA\FNS\logs\stdout.log" -Tail 100

# 服务自身日志
Get-Content "$env:LOCALAPPDATA\FNS\storage\logs\log.log" -Tail 100

# 状态
powershell -File "$env:LOCALAPPDATA\FNS\manage.ps1" status
```

---

## 服务端

| 现象 | 可能原因 | 处理 |
|---|---|---|
| `install.ps1` 下载失败 | GitHub 被墙/超时 | 加 `-Mirror ghproxy`；或手动下载后用 `-LocalArchive` |
| 端口被占用 | 9000 已被别的程序 | 换端口：`install.ps1 -Port 9100`；查占用：`Get-NetTCPConnection -LocalPort 9000` |
| `manage.ps1 start` 后立即退出 | 配置错误 / 端口冲突 / 权限 | 看 `logs\stdout.log`；确认 `config\config.yaml` 的 `http-port` |
| 本机能开、局域网打不开 | Windows 防火墙 | 管理员执行放行规则（见 01 文档第 4 节） |
| 重启电脑后服务没起来 | 登录任务只在登录后运行 | 改成开机任务/NSSM（见 01 文档 3.2） |
| 公司电脑锁屏后掉线 | 电源策略/休眠 | `powercfg /change standby-timeout-ac 0`，合盖设为"不操作" |
| 登录页 502/无法访问 | 反代没配 WebSocket | 用 Tailscale serve 或按 `deploy/nginx-fns.conf` 配 Upgrade 头 |
| 磁盘满 | 历史版本/回收站/备份 | 调小 `history-keep-versions`、`soft-delete-retention-time`，清理 `backups\` |
| `database is locked` | 同一目录跑了多个实例 | 只保留一个进程；`Get-CimInstance Win32_Process` 检查 |

---

## 连接与认证

| 现象 | 可能原因 | 处理 |
|---|---|---|
| 插件"服务已断开" | 地址/端口错、服务没起、网络不通 | 先在设备浏览器打开 `apiUrl`，能出登录页才说明网络通 |
| 401 / 令牌无效 | token 复制不全 / `auth-token-key` 被改 / 服务重装 | 服务端重新「复制 API 配置」，或核对 config |
| 403 需要管理员 | `user.admin-uid` 与当前 UID 不符 | 改成实际 UID 后重启（也可先设 0 验证） |
| 连上但不同步 | 库名不一致 / 只读模式 / 手动模式 | 三端核对「远端笔记库名」与开关 |
| 换了网络就连不上 | 有的设备填了局域网地址 | 统一改成 Tailscale/Cloudflare 地址 |
| 公司代理导致 HTTPS 失败 | 公司做了 TLS 中间人 | 用 Tailscale 绕过；或让 IT 加白名单 |

---

## Tailscale

| 现象 | 处理 |
|---|---|
| `tailscale up` 打不开登录页 | 公司网络限制？先手机热点试；或改用 Cloudflare Tunnel |
| `tailscale status` 显示 offline | 检查 Tailscale 服务是否运行、是否被安全软件拦截 |
| `tailscale serve` 提示版本旧 | 升级 Tailscale（需 ≥ 1.52） |
| 家里能 ping 通但 HTTPS 打不开 | 确认 `tailscale serve --bg 9000` 成功；`tailscale serve status` 查看 |
| 几个月后节点掉线 | 管理台把该机器设为 **Disable key expiry** |

---

## 客户端 / 同步

| 现象 | 处理 |
|---|---|
| 手机不后台同步 | 系统限制，打开 Obsidian 即同步；Android 关电池优化 |
| 大量 `skip`（规则缺目标） | 正常：规则有、包/版本里没有对应文件 |
| 冲突频繁 | 改「手动合并」；避免同一篇双端同时编辑 |
| 大附件失败 | 插件附件限制调 20–30 MB；服务端 `file-chunk-size` 调小 |
| 同步后配置乱了 | 关闭「配置项同步」，恢复 `.obsidian` 备份 |
| 插件商店打不开 | 手动放 `main.js/manifest.json/styles.css` 到 `.obsidian/plugins/fast-note-sync/` |

---

## 快速自检脚本

```powershell
$p = 9000
Get-Process fast-note-sync-service -ErrorAction SilentlyContinue | Select-Object Id,StartTime
Get-NetTCPConnection -LocalPort $p -State Listen -ErrorAction SilentlyContinue
try { (Invoke-WebRequest "http://127.0.0.1:$p/" -UseBasicParsing -TimeoutSec 5).StatusCode } catch { $_.Exception.Message }
Get-Content "$env:LOCALAPPDATA\FNS\logs\stdout.log" -Tail 20
```

如果以上都正常，问题基本在**网络路径**（Tailscale/防火墙/公司代理）或**插件配置**（地址/token/库名）。
