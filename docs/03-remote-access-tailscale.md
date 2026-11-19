# 03 · 跨网络访问（不在公司也能同步）

服务端在公司电脑上，公司网络通常：**没有公网 IP、不允许端口映射、还有防火墙/代理**。
所以"家里连公司"不能靠简单映射，推荐用**隧道**，让公司电脑主动向外建连。

---

## 方案对比

| 方案 | 需要公网 IP | 需要域名 | 需要管理员 | 稳定性 | 推荐度 |
|---|---|---|---|---|---|
| **Tailscale** | 否 | 否 | 装软件时需要 | 高（WireGuard） | ⭐⭐⭐⭐⭐ |
| Cloudflare Tunnel（命名隧道） | 否 | 是 | 装服务时需要 | 高 | ⭐⭐⭐⭐ |
| Cloudflare Tunnel（临时） | 否 | 否 | 否 | URL 每次重启变化 | ⭐⭐ 仅测试 |
| 公网 IP + 端口映射 + Caddy | 是 | 是 | 是 | 高 | ⭐ 公司一般不允许 |
| 仅局域网 | 否 | 否 | 否 | — | 出门不可用 |

---

## 方案 A：Tailscale（推荐）

原理：所有设备加入同一个 **tailnet**（虚拟局域网），公司电脑不需要公网 IP，NAT 由 Tailscale 打洞/中继解决，流量端到端加密。

### 1. 安装

- 公司电脑：<https://tailscale.com/download/windows>
- 家里 PC / 平板 / 手机：应用商店或官网下载
- 全部登录**同一个账号**（Google/Microsoft/GitHub 均可）

> 公司电脑安装需要管理员权限。若公司禁止安装，改用方案 B。

### 2. 登录并确认

```powershell
tailscale up
tailscale status
tailscale ip -4        # 例如 100.101.102.103
```

### 3. 给服务端开一个 HTTPS 地址（推荐）

Tailscale 1.52+ 支持 `serve`，把本机 9000 端口代理成 tailnet 内的 HTTPS：

```powershell
tailscale serve --bg 9000
```

输出类似：

```
https://fns-pc.tailxxxx.ts.net
```

把这个地址填进每台设备插件的「远端服务地址」即可。

> 好处：**不用开 Windows 防火墙**（serve 走本机回环），不用配证书，手机浏览器也能直接打开管理台。

也可以不用 serve，直接：

```
http://100.101.102.103:9000
```

但这样需要防火墙放行 9000，且插件会提示"HTTP 明文"（隧道本身仍加密）。

### 4. 验证

在**家里电脑**上：

```powershell
tailscale ping fns-pc
curl.exe -I https://fns-pc.tailxxxx.ts.net
```

能返回 `200/302` 即通。

### 5. 两个容易忽略的设置

1. **关闭节点密钥过期**：Tailscale 管理台 → Machines → 公司电脑 → `Disable key expiry`，
   否则几个月后节点掉线要重新登录。
2. **ACL（可选）**：tailnet 里只有你自己的设备时默认即可；团队共用时在
   Access Controls 里限制只允许你的设备访问 `fns-pc:9000`。

### 6. 开机自启

Tailscale 安装后默认开机自启；`tailscale serve` 的配置会持久化（`--bg`），重启后仍生效。

---

## 方案 B：Cloudflare Tunnel

适合"公司不让装 Tailscale，但允许运行一个 outbound 程序"的情况。

### B1. 临时隧道（5 分钟测试，URL 会变）

```powershell
# 下载 cloudflared.exe 后
.\cloudflared.exe tunnel --url http://127.0.0.1:9000
```

会输出 `https://random-words.trycloudflare.com`。
**缺点**：进程重启 URL 就变，插件要重新填地址；只适合验证连通性。

### B2. 命名隧道（稳定，需要域名）

1. 域名接入 Cloudflare（NS 指向 Cloudflare）；
2. 公司电脑：

```powershell
cloudflared tunnel login
cloudflared tunnel create fns
cloudflared tunnel route dns fns fns.example.com
```

3. 新建 `config.yml`：

```yaml
tunnel: fns
credentials-file: C:\Users\你\.cloudflared\<tunnel-id>.json
ingress:
  - hostname: fns.example.com
    service: http://127.0.0.1:9000
  - service: http_status:404
```

4. 安装为服务（管理员）：

```powershell
cloudflared service install
```

之后插件地址填 `https://fns.example.com`。

> 注意：Cloudflare 会解密流量（TLS 终止在 Cloudflare），笔记内容对 Cloudflare 可见。
> 对隐私敏感就用 Tailscale。

---

## 方案 C：公网 IP + 端口映射 + Caddy

只有在公司**真的有固定公网 IP 且允许入站**时才考虑：

1. 路由器把 443 映射到公司电脑；
2. 用 `deploy/Caddyfile` 起 Caddy 自动 HTTPS；
3. 插件填 `https://notes.example.com`。

公司网络一般封入站，且安全合规不允许，**不推荐**。

---

## 方案 D：仅局域网

插件地址填 `http://<公司电脑内网IP>:9000`，需要：

```powershell
netsh advfirewall firewall add rule name="FNS Obsidian Sync" dir=in action=allow protocol=TCP localport=9000
```

只适合"只在公司用"的场景。

---

## 安全建议

- 优先 Tailscale：不开任何公网端口；
- 服务端 `auth-token-key` 保持随机值，不要外泄；
- 注册完账号关闭注册；
- 手机丢失：Tailscale 管理台移除该设备 + 服务端重置 token；
- 定期备份 `storage/`（见 `04-backup-update.md`）。
