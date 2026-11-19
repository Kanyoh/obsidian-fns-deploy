# 一页纸操作卡：公司电脑 + Tailscale

> 目标：公司电脑当同步服务器，家里 PC / 平板 / 手机随时读写同一份 Obsidian 笔记。
> 全程约 10 分钟；只有装 Tailscale 需要管理员。

---

## A. 公司电脑（做一次，约 5 分钟）

```powershell
git clone https://github.com/Kanyoh/obsidian-fns-deploy.git
cd obsidian-fns-deploy\scripts\windows
powershell -ExecutionPolicy Bypass -File .\install.ps1
```

1. 打开脚本打印的 `http://127.0.0.1:9000`
2. 注册账号（例如 `Wink`，**新强密码**）
3. 左侧「笔记库」→「复制 API 配置」，**先存到便签**
4. 编辑 `%LOCALAPPDATA%\FNS\config\config.yaml`：
   ```yaml
   user:
     register-is-enable: false
   ```
   然后 `powershell -File "$env:LOCALAPPDATA\FNS\manage.ps1" restart`
5. 装 [Tailscale](https://tailscale.com/download/windows)，登录你的账号：
   ```powershell
   tailscale up
   tailscale serve --bg 9000
   ```
6. 记下输出的 `https://<机器名>.<tailnet>.ts.net` —— 这就是**所有设备**要填的地址

> 防睡眠（可选但推荐）：
> ```powershell
> powercfg /change standby-timeout-ac 0
> powercfg /change hibernate-timeout-ac 0
> ```
> 笔记本合盖请设为「不采取任何操作」。

---

## B. 家里 PC / 平板 / 手机（每台约 2 分钟）

1. 装 **Tailscale**，登录**同一个账号**；
2. Obsidian ≥ 1.8.7，装插件 **Fast Note Sync**；
3. 插件设置 →「粘贴服务端授权配置」→ 粘贴 A3 的 JSON；
4. 把「远端服务地址」改成 A6 的 `https://...ts.net`；
5. 「客户端名称」写设备名（`PC-家里` / `iPad` / `手机`）；
6. 首次顺序：**公司 PC 已上传 → 家里 PC 空库下载 → 平板/手机最后接入**。

---

## C. 验证（30 秒）

| 检查 | 命令 / 操作 | 通过标准 |
|---|---|---|
| 服务端存活 | 公司电脑：`manage.ps1 status` | `http: OK 200` |
| 跨网可达 | 家里电脑：`curl.exe -I https://<你的>.ts.net` | 返回 200/302 |
| 同步生效 | 公司 PC 改一篇笔记 | 5 秒内家里设备出现 |

---

## D. 三条排障

| 现象 | 先查 |
|---|---|
| 家里打不开 `https://...ts.net` | `tailscale status` 是否 online；`tailscale serve status` 是否 9000 |
| 插件 401 / 令牌无效 | 服务端重新「复制 API 配置」；确认没改过 `auth-token-key` |
| 公司电脑重启后服务没了 | 默认是"登录时启动"，没人登录就不会跑 → 改成开机任务（见 `docs/01-company-windows.md` 3.2） |

---

## E. 安全三条

- `config.yaml`（含 auth key）和 `storage/` **不要**提交到 Git；
- Tailscale 管理台把公司电脑设为 **Disable key expiry**，避免几个月后掉线；
- 手机丢了：Tailscale 移除设备 + 服务端重置 token。
