#!/usr/bin/env bash
# Hysteria 2 one-click installer for Ubuntu/Debian without a purchased domain.
# Uses the official Hysteria installer, a self-signed certificate with pinning,
# Salamander obfuscation, rollback, and an end-to-end local proxy test.
# Script version: 1.0.0

set -Eeuo pipefail
umask 077

SCRIPT_NAME="hysteria2-oneclick"
SCRIPT_VERSION="1.0.0"

HYSTERIA_BIN="/usr/local/bin/hysteria"
SERVICE_NAME="hysteria-server.service"
CONFIG_DIR="/etc/hysteria"
CONFIG_FILE="${CONFIG_DIR}/config.yaml"
CERT_FILE="${CONFIG_DIR}/server.crt"
KEY_FILE="${CONFIG_DIR}/server.key"
SECRETS_FILE="/root/hysteria2-secrets.env"
CLIENT_LINK_FILE="/root/hysteria2-client-link.txt"
INSTALLER_URL="https://get.hy2.sh/"

PORT=443
SERVER_ADDRESS=""
SNI="www.apple.com"
MASQUERADE_URL="https://www.apple.com/"
HYSTERIA_VERSION=""
ASSUME_YES=0
SHOW_LINK=0

TEMP_INSTALLER=""
TEMP_CERT=""
TEMP_KEY=""
TEMP_CONFIG=""
TEMP_CLIENT_CONFIG=""
TEMP_CLIENT_LOG=""
TEST_PID=""
SOCKS_PORT=""
BACKUP_DIR=""
HAD_OLD_CONFIG=0
HAD_OLD_CERT=0
HAD_OLD_KEY=0
WAS_ACTIVE=0
WAS_ENABLED=0
MUTATION_STARTED=0

log() {
  printf '\n\033[1;32m[%s]\033[0m %s\n' "$(date '+%H:%M:%S')" "$*"
}

warn() {
  printf '\033[1;33m警告：%s\033[0m\n' "$*" >&2
}

die() {
  printf '\033[1;31m错误：%s\033[0m\n' "$*" >&2
  return 1
}

usage() {
  cat <<'EOF'
用法：
  bash hysteria2-oneclick.sh [选项]

选项：
  --server-ip IP或域名      写入客户端链接的服务器公网地址；默认自动识别
  --port 端口               服务端 UDP 端口，默认 443
  --sni 域名                自签名证书的 SNI，默认 www.apple.com
  --masquerade-url URL      HTTP/3 伪装目标，默认 https://www.apple.com/
  --hysteria-version 版本   指定 Hysteria 版本，例如 v2.6.4；默认官方最新版
  --yes                     覆盖已有 Hysteria 配置时不再确认
  --show-link               成功后在终端显示完整客户端链接
  -v, --version             显示脚本版本
  -h, --help                显示帮助

示例：
  bash hysteria2-oneclick.sh
  bash hysteria2-oneclick.sh --server-ip 203.0.113.10 --show-link
  bash hysteria2-oneclick.sh --port 8443

说明：
  1. 本脚本使用 UDP，不会与同机的 Xray TCP 443 冲突。
  2. 不购买域名时使用自签名证书，并把证书 SHA-256 指纹写入客户端链接。
  3. 重复运行会重新生成密码、混淆密码和证书，旧客户端链接会失效。
EOF
}

cleanup() {
  set +e
  if [[ -n "$TEST_PID" ]]; then
    kill "$TEST_PID" 2>/dev/null || true
    wait "$TEST_PID" 2>/dev/null || true
  fi
  [[ -n "$TEMP_INSTALLER" ]] && rm -f -- "$TEMP_INSTALLER"
  [[ -n "$TEMP_CERT" ]] && rm -f -- "$TEMP_CERT"
  [[ -n "$TEMP_KEY" ]] && rm -f -- "$TEMP_KEY"
  [[ -n "$TEMP_CONFIG" ]] && rm -f -- "$TEMP_CONFIG"
  [[ -n "$TEMP_CLIENT_CONFIG" ]] && rm -f -- "$TEMP_CLIENT_CONFIG"
  [[ -n "$TEMP_CLIENT_LOG" ]] && rm -f -- "$TEMP_CLIENT_LOG"
  return 0
}

restore_file() {
  local old_flag="$1"
  local file_name="$2"
  local destination="$3"

  if [[ "$old_flag" -eq 1 && -f "${BACKUP_DIR}/${file_name}" ]]; then
    cp -a -- "${BACKUP_DIR}/${file_name}" "$destination"
  else
    rm -f -- "$destination"
  fi
}

rollback() {
  local rc="${1:-$?}"
  trap - ERR INT TERM
  set +e
  cleanup

  if [[ "$MUTATION_STARTED" -eq 1 ]]; then
    warn "部署失败，正在恢复原有 Hysteria 配置和服务状态。"
    systemctl stop "$SERVICE_NAME" >/dev/null 2>&1 || true
    mkdir -p "$CONFIG_DIR"
    restore_file "$HAD_OLD_CONFIG" "config.yaml" "$CONFIG_FILE"
    restore_file "$HAD_OLD_CERT" "server.crt" "$CERT_FILE"
    restore_file "$HAD_OLD_KEY" "server.key" "$KEY_FILE"

    if [[ "$WAS_ENABLED" -eq 1 ]]; then
      systemctl enable "$SERVICE_NAME" >/dev/null 2>&1 || true
    else
      systemctl disable "$SERVICE_NAME" >/dev/null 2>&1 || true
    fi

    if [[ "$WAS_ACTIVE" -eq 1 ]]; then
      systemctl restart "$SERVICE_NAME" >/dev/null 2>&1 || true
    else
      systemctl stop "$SERVICE_NAME" >/dev/null 2>&1 || true
    fi
  fi
  exit "$rc"
}

show_service_log() {
  warn "最近的 Hysteria 服务日志如下："
  journalctl -u "$SERVICE_NAME" -n 30 --no-pager 2>/dev/null || true
}

trap cleanup EXIT
trap 'rollback $?' ERR
trap 'rollback 130' INT
trap 'rollback 143' TERM

while [[ $# -gt 0 ]]; do
  case "$1" in
    --server-ip)
      [[ $# -ge 2 ]] || die "--server-ip 缺少参数"
      SERVER_ADDRESS="$2"
      shift 2
      ;;
    --port)
      [[ $# -ge 2 ]] || die "--port 缺少参数"
      PORT="$2"
      shift 2
      ;;
    --sni)
      [[ $# -ge 2 ]] || die "--sni 缺少参数"
      SNI="$2"
      shift 2
      ;;
    --masquerade-url)
      [[ $# -ge 2 ]] || die "--masquerade-url 缺少参数"
      MASQUERADE_URL="$2"
      shift 2
      ;;
    --hysteria-version)
      [[ $# -ge 2 ]] || die "--hysteria-version 缺少参数"
      HYSTERIA_VERSION="$2"
      shift 2
      ;;
    --yes)
      ASSUME_YES=1
      shift
      ;;
    --show-link)
      SHOW_LINK=1
      shift
      ;;
    -v|--version)
      printf '%s v%s\n' "$SCRIPT_NAME" "$SCRIPT_VERSION"
      exit 0
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "未知参数：$1"
      ;;
  esac
done

[[ "$EUID" -eq 0 ]] || die "请使用 root 用户运行此脚本。"
command -v apt-get >/dev/null 2>&1 || die "此脚本目前仅支持 Ubuntu/Debian（需要 apt-get 和 systemd）。"
command -v systemctl >/dev/null 2>&1 || die "未找到 systemctl。"
[[ "$PORT" =~ ^[0-9]+$ ]] || die "端口必须是数字。"
(( PORT >= 1 && PORT <= 65535 )) || die "端口必须在 1 到 65535 之间。"
[[ "$SNI" =~ ^[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?$ ]] || die "SNI 必须是普通域名。"

if [[ -f "$CONFIG_FILE" && "$ASSUME_YES" -ne 1 ]]; then
  warn "检测到已有 Hysteria 配置：${CONFIG_FILE}"
  warn "继续会备份并替换该配置，同时重新生成客户端凭据。"
  read -r -p "确认继续请输入 OVERWRITE：" CONFIRM
  [[ "$CONFIRM" == "OVERWRITE" ]] || die "用户取消。"
fi

if command -v ss >/dev/null 2>&1; then
  LISTENER="$(ss -H -lunp "( sport = :${PORT} )" 2>/dev/null || true)"
  if [[ -n "$LISTENER" && "$LISTENER" != *'hysteria'* ]]; then
    printf '%s\n' "$LISTENER" >&2
    die "UDP ${PORT} 已被其他程序占用。注意：TCP ${PORT} 被 Xray 使用不构成冲突。"
  fi
fi

if systemctl is-active --quiet "$SERVICE_NAME" 2>/dev/null; then
  WAS_ACTIVE=1
fi
if systemctl is-enabled --quiet "$SERVICE_NAME" 2>/dev/null; then
  WAS_ENABLED=1
fi

BACKUP_DIR="/root/hysteria2-backup.$(date +%Y%m%d%H%M%S)"
mkdir -p "$BACKUP_DIR"
if [[ -f "$CONFIG_FILE" ]]; then
  HAD_OLD_CONFIG=1
  cp -a -- "$CONFIG_FILE" "${BACKUP_DIR}/config.yaml"
fi
if [[ -f "$CERT_FILE" ]]; then
  HAD_OLD_CERT=1
  cp -a -- "$CERT_FILE" "${BACKUP_DIR}/server.crt"
fi
if [[ -f "$KEY_FILE" ]]; then
  HAD_OLD_KEY=1
  cp -a -- "$KEY_FILE" "${BACKUP_DIR}/server.key"
fi

log "安装基础依赖"
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y \
  curl openssl ca-certificates python3 iproute2

python3 - "$MASQUERADE_URL" <<'PY'
import sys
from urllib.parse import urlsplit

url = urlsplit(sys.argv[1])
if url.scheme != "https" or not url.hostname or url.username or url.password:
    raise SystemExit("伪装 URL 必须是普通的 https:// URL")
PY

if [[ -z "$SERVER_ADDRESS" ]]; then
  DETECTED_IP="$(curl -4 -fsS --connect-timeout 5 https://api.ipify.org 2>/dev/null || true)"
  if [[ -n "$DETECTED_IP" ]]; then
    SERVER_ADDRESS="$DETECTED_IP"
    log "自动识别服务器公网 IP：${SERVER_ADDRESS}"
  else
    read -r -p "未能自动识别，请输入服务器公网 IP：" SERVER_ADDRESS
  fi
fi

SERVER_ADDRESS="${SERVER_ADDRESS//[[:space:]]/}"
[[ -n "$SERVER_ADDRESS" ]] || die "服务器公网地址不能为空。"
python3 - "$SERVER_ADDRESS" <<'PY'
import ipaddress
import re
import sys

value = sys.argv[1]
if any(c in value for c in "/?#@[]"):
    try:
        ipaddress.ip_address(value.strip("[]"))
    except ValueError:
        raise SystemExit("服务器地址格式无效；只填写 IP 或域名，不要带协议和端口")
else:
    try:
        ipaddress.ip_address(value)
    except ValueError:
        if not re.fullmatch(r"[A-Za-z0-9](?:[A-Za-z0-9.-]*[A-Za-z0-9])?", value):
            raise SystemExit("服务器地址格式无效；只填写 IP 或域名，不要带协议和端口")
PY

log "检查伪装目标 ${MASQUERADE_URL}"
if ! curl -fsS -o /dev/null --connect-timeout 10 --max-time 20 "$MASQUERADE_URL"; then
  die "服务器无法访问伪装目标，请用 --masquerade-url 更换一个 HTTPS 网站。"
fi

log "通过 Hysteria 官方脚本安装或更新服务端"
TEMP_INSTALLER="$(mktemp --suffix=.sh /tmp/hysteria-install.XXXXXX)"
curl -fsSL "$INSTALLER_URL" -o "$TEMP_INSTALLER"
chmod 700 "$TEMP_INSTALLER"
MUTATION_STARTED=1
if [[ -n "$HYSTERIA_VERSION" ]]; then
  bash "$TEMP_INSTALLER" --version "$HYSTERIA_VERSION"
else
  bash "$TEMP_INSTALLER"
fi

[[ -x "$HYSTERIA_BIN" ]] || die "Hysteria 安装后未找到：${HYSTERIA_BIN}"
mkdir -p "$CONFIG_DIR"

log "生成认证密码、Salamander 混淆密码和自签名证书"
AUTH_PASSWORD="$(openssl rand -hex 24)"
OBFS_PASSWORD="$(openssl rand -hex 24)"
[[ ${#AUTH_PASSWORD} -eq 48 && ${#OBFS_PASSWORD} -eq 48 ]] || die "随机密码生成失败。"

TEMP_CERT="$(mktemp --suffix=.crt /tmp/hysteria2-cert.XXXXXX)"
TEMP_KEY="$(mktemp --suffix=.key /tmp/hysteria2-key.XXXXXX)"
openssl req -x509 -newkey rsa:2048 -sha256 -nodes \
  -days 3650 \
  -subj "/CN=${SNI}" \
  -addext "subjectAltName=DNS:${SNI}" \
  -keyout "$TEMP_KEY" \
  -out "$TEMP_CERT" >/dev/null 2>&1

CERT_FINGERPRINT="$(openssl x509 -noout -fingerprint -sha256 -in "$TEMP_CERT" | awk -F= '{print $2}')"
[[ "$CERT_FINGERPRINT" =~ ^([0-9A-F]{2}:){31}[0-9A-F]{2}$ ]] || die "证书指纹生成失败。"

TEMP_CONFIG="$(mktemp --suffix=.yaml /tmp/hysteria2-server.XXXXXX)"
export PORT SNI MASQUERADE_URL AUTH_PASSWORD OBFS_PASSWORD TEMP_CONFIG CERT_FILE KEY_FILE
python3 - <<'PY'
import json
import os

q = json.dumps
lines = [
    f"listen: {q(':' + os.environ['PORT'])}",
    "",
    "tls:",
    f"  cert: {q(os.environ['CERT_FILE'])}",
    f"  key: {q(os.environ['KEY_FILE'])}",
    "  sniGuard: strict",
    "",
    "auth:",
    "  type: password",
    f"  password: {q(os.environ['AUTH_PASSWORD'])}",
    "",
    "obfs:",
    "  type: salamander",
    "  salamander:",
    f"    password: {q(os.environ['OBFS_PASSWORD'])}",
    "",
    "masquerade:",
    "  type: proxy",
    "  proxy:",
    f"    url: {q(os.environ['MASQUERADE_URL'])}",
    "    rewriteHost: true",
    "",
]

with open(os.environ["TEMP_CONFIG"], "w", encoding="utf-8", newline="\n") as f:
    f.write("\n".join(lines))
os.chmod(os.environ["TEMP_CONFIG"], 0o600)
PY

SERVICE_USER="$(systemctl show "$SERVICE_NAME" -p User --value 2>/dev/null || true)"
SERVICE_USER="${SERVICE_USER:-root}"
if ! id "$SERVICE_USER" >/dev/null 2>&1; then
  die "服务用户 ${SERVICE_USER} 不存在。"
fi
SERVICE_GROUP="$(id -gn "$SERVICE_USER")"

install -o root -g "$SERVICE_GROUP" -m 640 "$TEMP_CONFIG" "$CONFIG_FILE"
install -o root -g "$SERVICE_GROUP" -m 644 "$TEMP_CERT" "$CERT_FILE"
install -o root -g "$SERVICE_GROUP" -m 640 "$TEMP_KEY" "$KEY_FILE"
chown root:"$SERVICE_GROUP" "$CONFIG_DIR"
chmod 750 "$CONFIG_DIR"

log "启动 Hysteria2（UDP ${PORT}）"
systemctl enable "$SERVICE_NAME" >/dev/null
if ! systemctl restart "$SERVICE_NAME"; then
  show_service_log
  die "Hysteria 服务启动失败。"
fi

for ((attempt = 0; attempt < 80; attempt++)); do
  if systemctl is-active --quiet "$SERVICE_NAME" && \
     ss -H -lun "( sport = :${PORT} )" 2>/dev/null | grep -q .; then
    break
  fi
  sleep 0.1
done

if ! systemctl is-active --quiet "$SERVICE_NAME"; then
  show_service_log
  die "Hysteria 服务没有保持运行。"
fi
if ! ss -H -lun "( sport = :${PORT} )" 2>/dev/null | grep -q .; then
  show_service_log
  die "Hysteria 未监听 UDP ${PORT}。"
fi

if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -q '^Status: active'; then
  log "UFW 已启用，放行 UDP ${PORT}"
  ufw allow "${PORT}/udp" >/dev/null
fi

log "执行 Hysteria2 端到端自测"
for ((candidate_port = 18080; candidate_port <= 18120; candidate_port++)); do
  if ! ss -H -lnt "( sport = :${candidate_port} )" 2>/dev/null | grep -q .; then
    SOCKS_PORT="$candidate_port"
    break
  fi
done
[[ -n "$SOCKS_PORT" ]] || die "无法找到本地 SOCKS5 自测端口。"

TEMP_CLIENT_CONFIG="$(mktemp --suffix=.yaml /tmp/hysteria2-client.XXXXXX)"
TEMP_CLIENT_LOG="$(mktemp --suffix=.log /tmp/hysteria2-client.XXXXXX)"
export SOCKS_PORT TEMP_CLIENT_CONFIG CERT_FINGERPRINT
python3 - <<'PY'
import json
import os

q = json.dumps
server = f"127.0.0.1:{os.environ['PORT']}"
lines = [
    f"server: {q(server)}",
    f"auth: {q(os.environ['AUTH_PASSWORD'])}",
    "",
    "tls:",
    f"  sni: {q(os.environ['SNI'])}",
    "  insecure: true",
    f"  pinSHA256: {q(os.environ['CERT_FINGERPRINT'])}",
    "",
    "obfs:",
    "  type: salamander",
    "  salamander:",
    f"    password: {q(os.environ['OBFS_PASSWORD'])}",
    "",
    "socks5:",
    f"  listen: {q('127.0.0.1:' + os.environ['SOCKS_PORT'])}",
    "  disableUDP: false",
    "",
]

with open(os.environ["TEMP_CLIENT_CONFIG"], "w", encoding="utf-8", newline="\n") as f:
    f.write("\n".join(lines))
os.chmod(os.environ["TEMP_CLIENT_CONFIG"], 0o600)
PY

"$HYSTERIA_BIN" client -c "$TEMP_CLIENT_CONFIG" >"$TEMP_CLIENT_LOG" 2>&1 &
TEST_PID=$!

for ((attempt = 0; attempt < 100; attempt++)); do
  if ss -H -lnt "( sport = :${SOCKS_PORT} )" 2>/dev/null | grep -q .; then
    break
  fi
  if ! kill -0 "$TEST_PID" 2>/dev/null; then
    break
  fi
  sleep 0.1
done

if ! kill -0 "$TEST_PID" 2>/dev/null || \
   ! ss -H -lnt "( sport = :${SOCKS_PORT} )" 2>/dev/null | grep -q .; then
  warn "临时客户端日志："
  tail -n 20 "$TEMP_CLIENT_LOG" >&2 || true
  die "临时 Hysteria 客户端启动失败。"
fi

SELF_TEST_HTTP="000"
for TEST_URL in \
  "https://cp.cloudflare.com/generate_204" \
  "https://www.gstatic.com/generate_204" \
  "https://www.apple.com/library/test/success.html"; do
  SELF_TEST_HTTP="$(curl -sS -o /dev/null -w '%{http_code}' \
    --socks5-hostname "127.0.0.1:${SOCKS_PORT}" \
    --connect-timeout 10 --max-time 20 \
    "$TEST_URL" 2>/dev/null || true)"
  if [[ -n "$SELF_TEST_HTTP" && "$SELF_TEST_HTTP" != "000" ]]; then
    break
  fi
done

if [[ -z "$SELF_TEST_HTTP" || "$SELF_TEST_HTTP" == "000" ]]; then
  warn "临时客户端日志："
  tail -n 20 "$TEMP_CLIENT_LOG" >&2 || true
  die "Hysteria2 端到端代理测试失败。请确认 VPS 网络允许 UDP。"
fi

kill "$TEST_PID" 2>/dev/null || true
wait "$TEST_PID" 2>/dev/null || true
TEST_PID=""

export SERVER_ADDRESS CLIENT_LINK_FILE SECRETS_FILE SCRIPT_VERSION
python3 - <<'PY'
import ipaddress
import os
from urllib.parse import quote, urlencode

host = os.environ["SERVER_ADDRESS"].strip("[]")
try:
    if ipaddress.ip_address(host).version == 6:
        host = f"[{host}]"
except ValueError:
    pass

query = urlencode({
    "insecure": "1",
    "pinSHA256": os.environ["CERT_FINGERPRINT"],
    "sni": os.environ["SNI"],
    "obfs": "salamander",
    "obfs-password": os.environ["OBFS_PASSWORD"],
})
label = quote("Hysteria2-v" + os.environ["SCRIPT_VERSION"], safe="")
uri = (
    "hysteria2://"
    + quote(os.environ["AUTH_PASSWORD"], safe="")
    + "@"
    + host
    + ":"
    + os.environ["PORT"]
    + "/?"
    + query
    + "#"
    + label
)

with open(os.environ["CLIENT_LINK_FILE"], "w", encoding="utf-8", newline="\n") as f:
    f.write(uri + "\n")

with open(os.environ["SECRETS_FILE"], "w", encoding="utf-8", newline="\n") as f:
    for key in ("AUTH_PASSWORD", "OBFS_PASSWORD", "CERT_FINGERPRINT", "SNI", "PORT"):
        f.write(f"{key}={os.environ[key]}\n")

os.chmod(os.environ["CLIENT_LINK_FILE"], 0o600)
os.chmod(os.environ["SECRETS_FILE"], 0o600)
PY

trap - ERR INT TERM
MUTATION_STARTED=0

HYSTERIA_VERSION_TEXT="$($HYSTERIA_BIN version 2>/dev/null | sed -n '1p' || true)"
printf '\n\033[1;32m部署成功。\033[0m\n'
printf '脚本版本：v%s\n' "$SCRIPT_VERSION"
printf '协议：Hysteria 2 + Salamander\n'
printf '传输：UDP/QUIC\n'
printf '端口：%s/udp\n' "$PORT"
printf 'SNI：%s\n' "$SNI"
printf '证书校验：自签名证书 + SHA-256 指纹固定\n'
[[ -n "$HYSTERIA_VERSION_TEXT" ]] && printf 'Hysteria：%s\n' "$HYSTERIA_VERSION_TEXT"
printf '端到端自测 HTTP：%s\n' "$SELF_TEST_HTTP"
printf '客户端链接文件：%s\n' "$CLIENT_LINK_FILE"
printf '凭据备份文件：%s\n' "$SECRETS_FILE"
if [[ "$HAD_OLD_CONFIG" -eq 1 || "$HAD_OLD_CERT" -eq 1 || "$HAD_OLD_KEY" -eq 1 ]]; then
  printf '原文件备份目录：%s\n' "$BACKUP_DIR"
fi

printf '\n下一步：\n'
printf '1. 在 VPS 提供商的防火墙/安全组中放行 UDP %s（不是 TCP）。\n' "$PORT"
printf '2. 执行：cat %s\n' "$CLIENT_LINK_FILE"
printf '3. 私下复制 hysteria2:// 链接，在 v2rayN 中“从剪贴板导入批量 URL”。\n'
printf '4. 不要截图、公开或提交客户端链接和凭据文件。\n'

if [[ "$SHOW_LINK" -eq 1 ]]; then
  printf '\n完整客户端链接（请勿公开）：\n'
  cat "$CLIENT_LINK_FILE"
fi
