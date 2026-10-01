# Hysteria2 一键部署脚本

面向 Ubuntu/Debian VPS 的 Hysteria 2 一键部署脚本。默认使用 UDP 443、Salamander 混淆、自签名证书和 SHA-256 证书指纹固定，不要求购买域名。

脚本可以与同一台服务器上的 Xray/VLESS 共存：Xray 使用 TCP 443，Hysteria2 使用 UDP 443，两者不会发生端口冲突。

[![Release](https://img.shields.io/github/v/release/kejichong/hysteria2-oneclick?display_name=tag)](https://github.com/kejichong/hysteria2-oneclick/releases)
[![License](https://img.shields.io/github/license/kejichong/hysteria2-oneclick)](LICENSE)
[![Shell](https://img.shields.io/badge/shell-bash-4EAA25?logo=gnubash&logoColor=white)](hysteria2-oneclick.sh)

## 项目特点

- 不需要购买或解析域名。
- 默认使用 UDP 443，可与同机 TCP 443 服务共存。
- 自动生成认证密码、Salamander 混淆密码和自签名证书。
- 客户端链接包含证书 SHA-256 指纹固定，避免只使用 `insecure`。
- 自动识别服务器公网 IPv4。
- 自动检测 UDP 端口占用，并处理已启用的 UFW。
- 安装后执行本机端到端代理测试，失败时自动恢复原配置。
- 生成可直接导入 v2rayN 的 `hysteria2://` 链接。

## 最快部署

先在 VPS 厂商安全组中放行 `UDP 443`，然后从 Windows PowerShell 登录服务器：

```powershell
ssh root@服务器IP
```

进入服务器后执行固定版本命令：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/kejichong/hysteria2-oneclick/refs/tags/v1.0.0/hysteria2-oneclick.sh) --show-link
```

完整说明、首次连接提示和 v2rayN 导入方法请继续阅读下文。

## 版本与下载

- [查看全部 Releases](https://github.com/kejichong/hysteria2-oneclick/releases)
- [下载 v1.0.0 源码](https://github.com/kejichong/hysteria2-oneclick/archive/refs/tags/v1.0.0.zip)
- [查看 v1.0.0 脚本](https://github.com/kejichong/hysteria2-oneclick/blob/v1.0.0/hysteria2-oneclick.sh)
- [获取 v1.0.0 Raw 地址](https://raw.githubusercontent.com/kejichong/hysteria2-oneclick/refs/tags/v1.0.0/hysteria2-oneclick.sh)

## 部署前准备

- 一台具有公网 IP 的 Ubuntu 22.04 LTS 或更高版本、Debian 11 或更高版本 VPS。
- VPS 的 root 登录密码或 SSH 密钥。
- 在 VPS 厂商控制台的防火墙/安全组中添加入站规则：

| 项目 | 设置 |
| --- | --- |
| 协议 | UDP |
| 端口 | 443 |
| 来源 | `0.0.0.0/0`；使用 IPv6 时另加 `::/0` |

注意：放行 TCP 443 不能代替放行 UDP 443。

## 推荐部署流程：只输入一次服务器密码

以下命令中的 `服务器IP` 要替换成 VPS 的真实公网 IP。不要填写服务器内部名称，例如 `VM236ABDFD9FF405D`。

### 第一步：登录服务器

在 Windows PowerShell 中执行：

```powershell
ssh root@服务器IP
```

第一次连接时可能询问是否信任主机指纹，输入：

```text
yes
```

然后输入一次 root 密码。密码输入过程中不会显示字符，输入完成后按回车。

看到类似下面的提示符，表示已经进入服务器：

```text
root@服务器名称:~#
```

### 第二步：从 GitHub 一键部署

在已经登录的服务器终端中执行：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/kejichong/hysteria2-oneclick/refs/tags/v1.0.0/hysteria2-oneclick.sh) --show-link
```

这一步不再要求输入 root 密码。脚本会自动识别服务器公网 IP，并完成安装、配置、启动和端到端测试。

如果暂时还没有创建 `v1.0.0` 标签，可以使用 main 分支：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/kejichong/hysteria2-oneclick/main/hysteria2-oneclick.sh) --show-link
```

正式存档和长期使用建议采用带版本标签的第一条命令，避免 main 分支后续变化影响旧服务器。

### 第三步：导入 v2rayN

成功后终端会显示：

```text
部署成功。
协议：Hysteria 2 + Salamander
传输：UDP/QUIC
端口：443/udp
```

同时会输出一条以 `hysteria2://` 开头的链接。完整复制该链接，在 v2rayN 中选择“从剪贴板导入批量 URL”，然后将新节点设为活动服务器。

如果以后需要重新显示链接，可以登录服务器后执行：

```bash
cat /root/hysteria2-client-link.txt
```

这条 `cat` 命令只负责显示已经生成的链接，不会重新部署、不会开放端口，也不会改变服务器配置。

## 脚本会自动完成什么

1. 安装 `curl`、OpenSSL、Python 3 和网络检查工具。
2. 通过 Hysteria 官方安装器安装或更新服务端。
3. 自动识别公网 IPv4；也可以通过 `--server-ip` 手动指定。
4. 生成随机认证密码和 Salamander 混淆密码。
5. 生成自签名证书，并将 SHA-256 指纹写入客户端链接。
6. 写入服务端配置并启动 `hysteria-server.service`。
7. 在 UFW 已启用时自动放行 UDP 443。
8. 从服务器本机执行一次完整 Hysteria2 代理测试。
9. 生成客户端链接和凭据备份。
10. 部署失败时恢复原配置和原服务状态。

脚本无法自动修改 VPS 厂商控制台中的安全组，因此部署前仍需人工放行 UDP 443。

## 文件路径

| 用途 | 路径 |
| --- | --- |
| Hysteria 程序 | `/usr/local/bin/hysteria` |
| 服务端配置 | `/etc/hysteria/config.yaml` |
| 自签名证书 | `/etc/hysteria/server.crt` |
| 证书私钥 | `/etc/hysteria/server.key` |
| 客户端链接 | `/root/hysteria2-client-link.txt` |
| 凭据备份 | `/root/hysteria2-secrets.env` |
| systemd 服务 | `hysteria-server.service` |

## 常用管理命令

查看运行状态：

```bash
systemctl status hysteria-server --no-pager -l
```

确认 UDP 443 正在监听：

```bash
ss -lunp | grep ':443'
```

查看最近日志：

```bash
journalctl -u hysteria-server -n 50 --no-pager
```

重启服务：

```bash
systemctl restart hysteria-server
```

重新显示客户端链接：

```bash
cat /root/hysteria2-client-link.txt
```

## 参数说明

```text
--server-ip IP或域名      手动指定写入客户端链接的服务器地址
--port 端口               UDP 端口，默认 443
--sni 域名                自签名证书 SNI，默认 www.apple.com
--masquerade-url URL      HTTP/3 伪装目标，默认 https://www.apple.com/
--hysteria-version 版本   指定 Hysteria 版本；默认官方最新版
--yes                     覆盖已有配置时不再确认
--show-link               成功后直接显示客户端链接
--version                 显示脚本版本
--help                    显示帮助
```

指定服务器 IP 的示例：

```bash
bash hysteria2-oneclick.sh --server-ip 203.0.113.10 --show-link
```

指定其他 UDP 端口的示例：

```bash
bash hysteria2-oneclick.sh --port 8443 --show-link
```

修改端口后，必须同时在 VPS 厂商安全组中放行对应的 UDP 端口。

## 重新运行脚本

检测到已有配置时，脚本会要求输入：

```text
OVERWRITE
```

这不是服务器密码，而是防止误覆盖的确认词。重新运行会生成新的认证密码、混淆密码和证书，因此旧客户端链接会失效，需要重新导入新链接。

## 常见问题

### 脚本显示成功，但 v2rayN 无法连接

首先检查 VPS 厂商安全组是否放行了 `UDP 443`。只放行 TCP 443 对 Hysteria2 无效。然后在服务器执行：

```bash
systemctl is-active hysteria-server
ss -lunp | grep ':443'
```

### `cat /root/hysteria2-client-link.txt` 有什么作用

它只负责重新显示已经生成的客户端链接，不会重新安装服务，也不会修改防火墙或端口。

### TCP 443 已被 Xray 占用，还能部署吗

可以。TCP 443 和 UDP 443 是两个不同的监听端口。本脚本仅使用 UDP 443，不会停止或覆盖 Xray 的 TCP 443 服务。

### 重新执行脚本后旧节点为什么失效

重新部署会生成新的认证密码、混淆密码和证书。需要重新复制 `/root/hysteria2-client-link.txt` 中的新链接并导入客户端。

### 如何确认问题发生在服务器还是客户端

脚本结束前会通过临时 Hysteria2 客户端执行端到端代理测试。如果显示“部署成功”和有效 HTTP 状态码，通常说明服务端配置正确，应继续检查云安全组、客户端导入参数和本地网络对 UDP 的支持。

## 安全提示

- 不要公开 `hysteria2://` 链接。
- 不要把 `/root/hysteria2-secrets.env` 上传到 GitHub。
- 不要在截图中暴露认证密码、混淆密码或完整客户端链接。
- 建议使用版本标签对应的 Raw 链接部署，并在发布页面提供 SHA-256 校验值。

## 官方资料

- [Hysteria 2 官方安装脚本](https://v2.hysteria.network/docs/getting-started/Server-Installation-Script/)
- [Hysteria 2 服务端配置](https://v2.hysteria.network/docs/getting-started/Server/)
- [Hysteria 2 完整服务端配置](https://v2.hysteria.network/docs/advanced/Full-Server-Config/)
- [Hysteria 2 URI 格式](https://v2.hysteria.network/docs/developers/URI-Scheme/)

## 许可

本项目采用 MIT License。
