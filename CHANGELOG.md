# 更新记录

## v1.0.0

- 使用 Hysteria 官方安装器安装或更新服务端。
- 支持 Ubuntu/Debian、systemd 和无域名部署。
- 默认使用 UDP 443、Salamander 混淆和 HTTP/3 伪装。
- 使用自签名证书，并在客户端链接中固定 SHA-256 指纹。
- 自动识别服务器公网 IPv4。
- 自动处理启用状态下的 UFW 规则。
- 增加端到端本机代理测试和失败回滚。
- 生成 v2rayN 可导入的 `hysteria2://` 链接。
