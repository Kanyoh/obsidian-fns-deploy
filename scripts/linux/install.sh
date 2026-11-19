#!/usr/bin/env bash
# One-click installer for Fast Note Sync Service on Linux (systemd, no Docker).
#
#   sudo bash install.sh [--port 9000] [--version 3.6.1] [--dir /opt/fns] [--mirror ghproxy]
#
# Tested on Debian/Ubuntu; needs curl, tar, systemctl.
set -euo pipefail

PORT=9000
VERSION=3.6.1
DIR=/opt/fns
MIRROR=auto

while [[ $# -gt 0 ]]; do
  case "$1" in
    --port) PORT="$2"; shift 2 ;;
    --version) VERSION="$2"; shift 2 ;;
    --dir) DIR="$2"; shift 2 ;;
    --mirror) MIRROR="$2"; shift 2 ;;
    -h|--help) sed -n '2,8p' "$0"; exit 0 ;;
    *) echo "unknown option: $1"; exit 1 ;;
  esac
done

if [[ "$(id -u)" -ne 0 ]]; then
  echo "please run as root (sudo)"; exit 1
fi

ARCH=$(uname -m)
case "$ARCH" in
  x86_64|amd64) A=amd64 ;;
  aarch64|arm64) A=arm64 ;;
  armv7l|armv7) A=armv7l ;;
  *) echo "unsupported arch: $ARCH"; exit 1 ;;
esac

ASSET="fast-note-sync-service-${VERSION}-linux-${A}.tar.gz"
OFFICIAL="https://github.com/haierkeys/fast-note-sync-service/releases/download/${VERSION}/${ASSET}"
MIRRORED="https://gh-proxy.com/${OFFICIAL}"

echo "==> installing Fast Note Sync Service ${VERSION} (${A}) to ${DIR}"
mkdir -p "$DIR" "$DIR/config" "$DIR/logs" "$DIR/backups"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

download() {
  local url=$1
  echo "    downloading: $url"
  curl -fL --retry 3 --retry-all-errors --connect-timeout 15 -o "$TMP/$ASSET" "$url"
}

if [[ "$MIRROR" != "github" ]]; then
  download "$MIRRORED" || true
fi
if [[ ! -s "$TMP/$ASSET" && "$MIRROR" != "ghproxy" ]]; then
  download "$OFFICIAL"
fi
[[ -s "$TMP/$ASSET" ]] || { echo "download failed"; exit 1; }

echo "==> extracting"
tar -xzf "$TMP/$ASSET" -C "$TMP"
install -m 0755 "$TMP/fast-note-sync-service" "$DIR/fast-note-sync-service"

echo "==> writing config"
KEY=$(head -c 32 /dev/urandom | base64 | tr -d '\n')
sed -e "s/http-port: \":[0-9]*\"/http-port: \":${PORT}\"/" \
    -e "s/auth-token-key: .*/auth-token-key: ${KEY}/" \
    "$TMP/config/config.yaml" > "$DIR/config/config.yaml"

if [[ ! -f "$DIR/config/config.yaml" || ! -s "$DIR/config/config.yaml" ]]; then
  echo "config generation failed"; exit 1
fi

echo "==> installing systemd unit"
cat > /etc/systemd/system/fns.service <<EOF
[Unit]
Description=Fast Note Sync Service
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory=${DIR}
ExecStart=${DIR}/fast-note-sync-service run -c config/config.yaml
Restart=always
RestartSec=3
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now fns.service
sleep 2
systemctl --no-pager --lines=5 status fns.service || true

echo
echo "==> done"
echo "    local:  http://127.0.0.1:${PORT}"
for ip in $(hostname -I 2>/dev/null); do echo "    lan:    http://${ip}:${PORT}"; done
echo
echo "next:"
echo "  1. open the URL, register your account"
echo "  2. Web UI -> Vaults -> Copy API Config"
echo "  3. paste into Obsidian -> Fast Note Sync"
echo
echo "manage: systemctl status|restart|stop fns"
echo "backup: tar czf /root/fns-\$(date +%F).tar.gz -C ${DIR} config storage"
