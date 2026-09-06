#!/usr/bin/env bash
set -Eeuo pipefail

APP_DIR="/opt/9router"
DATA_DIR="${APP_DIR}/data"
ENV_FILE="${APP_DIR}/.env"
CONTAINER_NAME="9router"
IMAGE="decolua/9router:latest"
PORT="20128"
UPDATE_SCRIPT="${APP_DIR}/update.sh"
UPDATE_SERVICE="/etc/systemd/system/9router-update.service"
UPDATE_TIMER="/etc/systemd/system/9router-update.timer"

log(){ echo "[+] $*"; }
fail(){ echo "[ERROR] $*" >&2; exit 1; }

[[ $EUID -eq 0 ]] || fail "Run this installer as root."

if [[ ! -f /etc/os-release ]]; then fail "Cannot detect operating system."; fi
source /etc/os-release

case "$(uname -m)" in
  x86_64|amd64|aarch64|arm64) ;;
  *) fail "Unsupported architecture: $(uname -m)" ;;
esac

if command -v apt-get >/dev/null 2>&1; then
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -qq
  apt-get install -y -qq ca-certificates curl openssl >/dev/null
else
  fail "This installer currently supports Debian/Ubuntu systems."
fi

if ! command -v docker >/dev/null 2>&1; then
  log "Installing Docker..."
  curl -fsSL https://get.docker.com | sh
fi

systemctl enable --now docker

docker info >/dev/null 2>&1 || fail "Docker is not running."

mkdir -p "${DATA_DIR}"
chmod 700 "${APP_DIR}" "${DATA_DIR}"

if [[ ! -f "${ENV_FILE}" ]]; then
  log "Generating 9Router configuration..."
  JWT_SECRET="$(openssl rand -hex 32)"
  API_KEY_SECRET="$(openssl rand -hex 32)"
  MACHINE_ID_SALT="$(openssl rand -hex 32)"
  INITIAL_PASSWORD="$(openssl rand -base64 32 | tr -dc 'A-Za-z0-9' | head -c 24)"

  cat > "${ENV_FILE}" <<EOF
NODE_ENV=production
PORT=20128
HOSTNAME=0.0.0.0
DATA_DIR=/app/data
JWT_SECRET=${JWT_SECRET}
INITIAL_PASSWORD=${INITIAL_PASSWORD}
API_KEY_SECRET=${API_KEY_SECRET}
MACHINE_ID_SALT=${MACHINE_ID_SALT}
NEXT_PUBLIC_BASE_URL=http://127.0.0.1:20128
NEXT_PUBLIC_CLOUD_URL=https://9router.com
ENABLE_REQUEST_LOGS=false
EOF
  chmod 600 "${ENV_FILE}"
else
  log "Keeping existing configuration."
fi

log "Pulling ${IMAGE}..."
docker pull "${IMAGE}"

docker rm -f "${CONTAINER_NAME}" >/dev/null 2>&1 || true

log "Starting 9Router on port ${PORT}..."
docker run -d \
  --name "${CONTAINER_NAME}" \
  --restart unless-stopped \
  -p "${PORT}:${PORT}" \
  --env-file "${ENV_FILE}" \
  -v "${DATA_DIR}:/app/data" \
  "${IMAGE}" >/dev/null

sleep 8

docker ps --format '{{.Names}}' | grep -qx "${CONTAINER_NAME}" || {
  docker logs --tail 100 "${CONTAINER_NAME}" || true
  fail "9Router failed to start."
}

cat > "${UPDATE_SCRIPT}" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
APP_DIR="/opt/9router"
DATA_DIR="${APP_DIR}/data"
ENV_FILE="${APP_DIR}/.env"
CONTAINER_NAME="9router"
IMAGE="decolua/9router:latest"
PORT="20128"
LOG_FILE="${APP_DIR}/update.log"
exec >> "${LOG_FILE}" 2>&1

echo "=== 9Router update $(date -Is) ==="
docker pull "${IMAGE}"
LATEST="$(docker image inspect "${IMAGE}" -f '{{.Id}}')"
CURRENT=""
if docker container inspect "${CONTAINER_NAME}" >/dev/null 2>&1; then
  CURRENT="$(docker inspect "${CONTAINER_NAME}" -f '{{.Image}}')"
fi
if [[ -n "${CURRENT}" && "${CURRENT}" == "${LATEST}" ]]; then
  echo "No update available."
  exit 0
fi

docker rm -f "${CONTAINER_NAME}" >/dev/null 2>&1 || true
docker run -d \
  --name "${CONTAINER_NAME}" \
  --restart unless-stopped \
  -p "${PORT}:${PORT}" \
  --env-file "${ENV_FILE}" \
  -v "${DATA_DIR}:/app/data" \
  "${IMAGE}"

sleep 8
docker ps --format '{{.Names}}' | grep -qx "${CONTAINER_NAME}" || {
  docker logs --tail 100 "${CONTAINER_NAME}" || true
  exit 1
}
docker image prune -f
echo "Update successful."
EOF
chmod 700 "${UPDATE_SCRIPT}"

cat > "${UPDATE_SERVICE}" <<EOF
[Unit]
Description=9Router automatic Docker update
After=docker.service
Requires=docker.service

[Service]
Type=oneshot
ExecStart=${UPDATE_SCRIPT}
EOF

cat > "${UPDATE_TIMER}" <<EOF
[Unit]
Description=Daily 9Router update check

[Timer]
OnCalendar=*-*-* 04:30:00
Persistent=true
RandomizedDelaySec=10m

[Install]
WantedBy=timers.target
EOF

systemctl daemon-reload
systemctl enable --now 9router-update.timer

if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -q 'Status: active'; then
  ufw allow "${PORT}/tcp" >/dev/null
fi

PUBLIC_IP="$(curl -4 -fsS --max-time 5 https://api.ipify.org 2>/dev/null || true)"
[[ -n "${PUBLIC_IP}" ]] || PUBLIC_IP="SERVER_IP"

PASSWORD="$(grep '^INITIAL_PASSWORD=' "${ENV_FILE}" | cut -d= -f2- || true)"

echo
echo '=============================================='
echo '       9Router installation complete'
echo '=============================================='
echo
echo "Dashboard: http://${PUBLIC_IP}:${PORT}"
echo "API:       http://${PUBLIC_IP}:${PORT}/v1"
echo "Data:      ${DATA_DIR}"
echo "Config:    ${ENV_FILE}"
echo "Updates:   daily at 04:30 (random delay up to 10m)"
if [[ -n "${PASSWORD}" ]]; then
  echo
echo "Initial password: ${PASSWORD}"
  echo "SAVE THIS PASSWORD."
fi
echo
echo
echo 'Useful commands:'
echo '  docker logs -f 9router'
echo '  docker restart 9router'
echo '  docker ps'
echo '  systemctl status 9router-update.timer'
echo '  journalctl -u 9router-update.service'
echo
echo '=============================================='
