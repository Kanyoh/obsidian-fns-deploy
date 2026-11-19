# 04 · 备份、升级与换机迁移

服务器上只有两样东西值得备份：

```
config/    配置（含 auth-token-key、端口）
storage/   笔记、附件、SQLite 数据库、历史版本、回收站
```

---

## 1. 一键备份

```powershell
powershell -File "$env:LOCALAPPDATA\FNS\manage.ps1" backup
```

行为：

1. 停止服务（避免 SQLite 写一半）；
2. 把 `config` + `storage` 压成 `backups\fns-backup-yyyyMMdd-HHmmss.zip`；
3. 只保留最近 **7** 份；
4. 如果之前服务在运行，会自动重新启动。

### 建议频率

| 数据量 | 频率 | 备注 |
|---|---|---|
| 个人笔记（< 1 GB） | 每天一次 | 用任务计划调用 |
| 附件多（> 1 GB） | 每周 + 重要改动前 | 备份文件会比较大 |

用计划任务每天 03:00 自动备份：

```powershell
schtasks /Create /SC DAILY /ST 03:00 /TN "FNS-Backup" /RL LIMITED `
  /TR "powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$env:LOCALAPPDATA\FNS\manage.ps1`" backup" /F
```

### 异地保存

`backups\` 只是本地副本。建议再用以下任一方式同步出去：

- OneDrive / 企业网盘同步该目录；
- 定期复制到移动硬盘；
- 服务端自带的对象存储备份（S3/WebDAV，见上游配置 `storage:` 与备份章节）。

---

## 2. 恢复

```powershell
# 1) 停止服务
powershell -File "$env:LOCALAPPDATA\FNS\manage.ps1" stop

# 2) 备份当前（以防万一）
Rename-Item "$env:LOCALAPPDATA\FNS\storage" "storage.bad"
Rename-Item "$env:LOCALAPPDATA\FNS\config"  "config.bad"

# 3) 解压备份
Expand-Archive "$env:LOCALAPPDATA\FNS\backups\fns-backup-20261120-030000.zip" -DestinationPath "$env:LOCALAPPDATA\FNS\restore"
Move-Item "$env:LOCALAPPDATA\FNS\restore\config"  "$env:LOCALAPPDATA\FNS\config"
Move-Item "$env:LOCALAPPDATA\FNS\restore\storage" "$env:LOCALAPPDATA\FNS\storage"

# 4) 启动
powershell -File "$env:LOCALAPPDATA\FNS\manage.ps1" start
```

> 恢复后所有设备插件里的 token 仍然有效（`auth-token-key` 来自备份的 config）。

---

## 3. 升级服务端

```powershell
powershell -File "$env:LOCALAPPDATA\FNS\manage.ps1" update -Version 3.6.1
```

行为：下载新版本 → 停服务 → 只替换 exe（**保留 config 和 storage**）→ 启动 → 打印状态。

升级前建议先 `backup`。版本号在 [Releases](https://github.com/haierkeys/fast-note-sync-service/releases) 查。

> 跨大版本升级前看上游 CHANGELOG；数据库一般自动迁移（`database.auto-migrate: true`）。

---

## 4. 换电脑 / 迁移到新机器

1. 旧机器：`manage.ps1 backup`，把 zip 拷到新机器；
2. 新机器：跑 `install.ps1 -NoStart -NoTask`（只装程序）；
3. 解压备份，把 `config`、`storage` 覆盖到新安装目录；
4. `manage.ps1 start`；
5. 确认 `http://127.0.0.1:9000` 能登录、笔记数量正确；
6. 旧机器 `manage.ps1 uninstall`（保留数据的话先备份）；
7. 如果用了 Tailscale：新机器 `tailscale up` + `tailscale serve --bg 9000`，
   把旧机器从 tailnet 移除，或把 DNS 名改到新机器；
8. 客户端**不用改**（如果地址没变）；地址变了就重新「粘贴服务端授权配置」。

---

## 5. 版本兼容

| 功能 | 插件 | 服务端 |
|---|---|---|
| 基础笔记同步 | ≥ 1.0 | ≥ 0.9 |
| 附件同步 | ≥ 1.0 | ≥ 0.9 |
| 配置项同步 | ≥ 1.4 | ≥ 1.0 |
| 笔记历史 | ≥ 1.x | ≥ 1.2 |
| 本文验证组合 | **2.4.0** | **3.6.1** |

建议：**服务端固定小版本**，插件跟随商店更新；升级前备份。
