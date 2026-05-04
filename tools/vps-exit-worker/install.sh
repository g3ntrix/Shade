#!/usr/bin/env bash
set -euo pipefail

APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_NAME="shade-exit"

need_cmd() {
  command -v "$1" >/dev/null 2>&1
}

ensure_node() {
  if need_cmd node; then
    return
  fi
  apt-get update
  apt-get install -y curl
  curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
  apt-get install -y nodejs
}

ensure_pm2() {
  if need_cmd pm2; then
    return
  fi
  npm install -g pm2
}

port_in_use() {
  local port="$1"
  ss -tlnH "( sport = :${port} )" | grep -q .
}

pick_port() {
  local preferred="${RELAY_PORT:-18081}"
  if ! port_in_use "$preferred"; then
    echo "$preferred"
    return
  fi
  for p in 18082 18083 18084 18085 18086 18087 18088 18089 18090 28081 28082; do
    if ! port_in_use "$p"; then
      echo "$p"
      return
    fi
  done
  return 1
}

gen_psk() {
  if [ -n "${EXIT_NODE_PSK:-}" ]; then
    echo "${EXIT_NODE_PSK}"
    return
  fi
  if need_cmd openssl; then
    openssl rand -hex 24
    return
  fi
  node -e "console.log(require('crypto').randomBytes(24).toString('hex'))"
}

PORT_VALUE="$(pick_port)" || {
  echo "ERROR: no free relay port found in candidate list." >&2
  exit 1
}
PSK_VALUE="$(gen_psk)"

cat > "${APP_DIR}/ecosystem.config.cjs" <<EOF
module.exports = {
  apps: [
    {
      name: "${APP_NAME}",
      script: "server.js",
      node_args: "--max-http-header-size=65536",
      env: {
        PORT: "${PORT_VALUE}",
        EXIT_NODE_PSK: "${PSK_VALUE}",
      },
    },
  ],
};
EOF

ensure_node
ensure_pm2

cd "${APP_DIR}"
pm2 delete "${APP_NAME}" >/dev/null 2>&1 || true
pm2 start ecosystem.config.cjs
pm2 save
pm2 startup systemd -u root --hp /root >/tmp/shade-exit-pm2-startup.txt 2>/dev/null || true

PUBLIC_IP="$(curl -4 -fsS https://ifconfig.me 2>/dev/null || true)"
if [ -z "${PUBLIC_IP}" ]; then
  PUBLIC_IP="$(hostname -I 2>/dev/null | awk '{print $1}')"
fi

RELAY_URL="http://YOUR_VPS_IP:${PORT_VALUE}"
if [ -n "${PUBLIC_IP}" ]; then
  RELAY_URL="http://${PUBLIC_IP}:${PORT_VALUE}"
fi

echo
echo "=== Shade Exit Relay Ready ==="
echo "Relay URL: ${RELAY_URL}"
echo "Exit PSK : ${PSK_VALUE}"
echo
echo "Use these in Shade -> Settings -> Exit node."
echo
