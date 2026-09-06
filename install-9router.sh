#!/usr/bin/env bash
set -Eeuo pipefail

APP_DIR="/opt/9router"
DATA_DIR="$APP_DIR/data"
ENV_FILE="$APP_DIR/.env"
CONTAINER_NAME="9router"
IMAGE="decolua/9router:latest"
PORT="20128"
UPDATE_SCRIPT="$APP_DIR/update.sh"
UPDATE_SERVICE="/etc/systemd/system/9router-update.service"
UPDATE_TIMER="/etc/systemd/system/9router-update.timer"
SELF="9router-installer"

log(){ echo "[+] $*"; }
warn(){ echo "[!] $*"; }
fail(){ echo "[ERROR] $*" >&2; exit 1; }
need_root(){ [[ $EUID -eq 0 ]] || fail "Run as root: sudo bash $0"; }

install_deps(){
  command -v apt-get >/dev/null 2>&1 || fail "Only Debian/Ubuntu is supported."
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -qq
  apt-get install -y -qq ca-certificates curl openssl >/dev/null
}

ensure_docker(){
  if ! command -v docker >/dev/null 2>&1; then
    log "Installing Docker from the official installer..."
    curl -fsSL https://get.docker.com | sh
  fi
  systemctl enable --now docker
  docker info >/dev/null 2>&1 || fail "Docker is not running."
}

write_env(){
  mkdir -p "$DATA_DIR"
  chmod 700 "$APP_DIR" "$DATA_DIR"
  if [[ -f "$ENV_FILE" ]]; then
    log "Keeping existing configuration."
    return
  fi
  local jwt api salt pass
  jwt="$(openssl rand -hex 32)"
  api="$(openssl rand -hex 32)"
  salt="$(openssl rand -hex 32)"
  pass="$(openssl rand -base64 32 | tr -dc 'A-Za-z0-9' | head -c 24)"
  cat > "$ENV_FILE" <<EOF
NODE_ENV=production
PORT=$PORT
HOSTNAME=0.0.0.0
DATA_DIR=/app/data
JWT_SECRET=$jwt
INITIAL_PASSWORD=$pass
API_KEY_SECRET=$api
MACHINE_ID_SALT=$salt
NEXT_PUBLIC_BASE_URL=http://127.0.0.1:$PORT
NEXT_PUBLIC_CLOUD_URL=https://9router.com
ENABLE_REQUEST_LOGS=false
EOF
  chmod 600 "$ENV_FILE"
}

run_container(){
  docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true
  docker run -d \
    --name "$CONTAINER_NAME" \
    --restart unless-stopped \
    -p "$PORT:$PORT" \
    --env-file "$ENV_FILE" \
    -v "$DATA_DIR:/app/data" \
    "$IMAGE" >/dev/null
  sleep 5
  docker ps --format '{{.Names}}' | grep -qx "$CONTAINER_NAME" || {
    docker logs --tail 100 "$CONTAINER_NAME" || true
    fail "9Router failed to start."
  }
}

write_update(){
cat > "$UPDATE_SCRIPT" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
APP_DIR="/opt/9router"
DATA_DIR="$APP_DIR/data"
ENV_FILE="$APP_DIR/.env"
CONTAINER_NAME="9router"
IMAGE="decolua/9router:latest"
PORT="20128"
LOG_FILE="$APP_DIR/update.log"
exec >> "$LOG_FILE" 2>&1

echo "=== 9Router update $(date -Is) ==="
docker pull "$IMAGE"
LATEST="$(docker image inspect "$IMAGE" -f '{{.Id}}')"
CURRENT="$(docker inspect "$CONTAINER_NAME" -f '{{.Image}}' 2>/dev/null || true)"
if [[ -n "$CURRENT" && "$CURRENT" == "$LATEST" ]]; then
  echo "No update available."
  exit 0
fi
docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true
docker run -d --name "$CONTAINER_NAME" --restart unless-stopped -p "$PORT:$PORT" --env-file "$ENV_FILE" -v "$DATA_DIR:/app/data" "$IMAGE"
sleep 5
docker ps --format '{{.Names}}' | grep -qx "$CONTAINER_NAME" || { docker logs --tail 100 "$CONTAINER_NAME" || true; exit 1; }
docker image prune -f
echo "Update successful."
EOF
chmod 700 "$UPDATE_SCRIPT"
cat > "$UPDATE_SERVICE" <<EOF
[Unit]
Description=9Router automatic Docker update
After=docker.service
Requires=docker.service
[Service]
Type=oneshot
ExecStart=$UPDATE_SCRIPT
EOF
cat > "$UPDATE_TIMER" <<EOF
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
}

cli_token(){
  docker exec "$CONTAINER_NAME" node -e '
const fs=require("fs"),crypto=require("crypto");
function read(p){try{return fs.readFileSync(p,"utf8").trim()}catch(e){return ""}}
let id=read("/app/data/machine-id")||read("/etc/machine-id");
const secret=read("/app/data/auth/cli-secret");
if(!id||!secret) process.exit(2);
console.log(crypto.createHash("sha256").update(id+"9r-cli-auth"+secret).digest("hex").slice(0,16));
' 2>/dev/null
}

tunnel_request(){
  local action="$1" token code body
  token="$(cli_token || true)"
  [[ -n "$token" ]] || fail "CLI token is not ready yet. Wait for 9Router to initialize and try again."
  body="$(mktemp)"
  code="$(curl -sS -o "$body" -w '%{http_code}' -X POST -H "x-9r-cli-token: $token" "http://127.0.0.1:$PORT/api/tunnel/$action" || true)"
  cat "$body"; echo
  rm -f "$body"
  [[ "$code" =~ ^2 ]] || return 1
}

install_9router(){
  install_deps
  ensure_docker
  write_env
  log "Pulling $IMAGE..."
  docker pull "$IMAGE"
  run_container
  write_update
  if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -q 'Status: active'; then
    ufw allow "$PORT/tcp" >/dev/null
  fi
  local ip pass
  ip="$(curl -4 -fsS --max-time 5 https://api.ipify.org 2>/dev/null || echo SERVER_IP)"
  pass="$(grep '^INITIAL_PASSWORD=' "$ENV_FILE" | cut -d= -f2-)"
  echo
  echo "=============================================="
  echo "9Router installation complete"
  echo "Dashboard: http://$ip:$PORT"
  echo "API:       http://$ip:$PORT/v1"
  echo "Updates:   daily at 04:30"
  echo "Initial password: $pass"
  echo "=============================================="
  echo
  read -r -p "Enable 9Router Tunnel now? [y/N]: " answer
  if [[ "$answer" =~ ^[Yy]$ ]]; then
    sleep 3
    tunnel_request enable && log "Tunnel enabled successfully." || warn "Tunnel could not be enabled. Check logs with option 6."
  fi
}

update_9router(){ [[ -x "$UPDATE_SCRIPT" ]] || fail "9Router is not installed."; "$UPDATE_SCRIPT"; tail -n 30 "$APP_DIR/update.log" 2>/dev/null || true; }
status_9router(){ docker ps --filter "name=^/${CONTAINER_NAME}$"; echo; curl -sS "http://127.0.0.1:$PORT/api/health" 2>/dev/null || true; echo; }
logs_9router(){ docker logs --tail 150 "$CONTAINER_NAME"; }
tunnel_status(){ local token="$(cli_token || true)"; [[ -n "$token" ]] || fail "CLI token unavailable."; curl -sS -H "x-9r-cli-token: $token" "http://127.0.0.1:$PORT/api/tunnel/status"; echo; }
uninstall_9router(){
  read -r -p "This removes 9Router and ALL its data. Continue? [y/N]: " answer
  [[ "$answer" =~ ^[Yy]$ ]] || { echo "Cancelled."; return; }
  systemctl disable --now 9router-update.timer 2>/dev/null || true
  rm -f "$UPDATE_SERVICE" "$UPDATE_TIMER"
  systemctl daemon-reload
  docker rm -f "$CONTAINER_NAME" 2>/dev/null || true
  docker image rm "$IMAGE" 2>/dev/null || true
  rm -rf "$APP_DIR"
  echo "9Router completely removed. Docker itself was kept installed."
}

menu(){
  while true; do
    echo
    echo "========== $SELF =========="
    echo "1) Install / Repair 9Router"
    echo "2) Update now"
    echo "3) Status"
    echo "4) Tunnel status"
    echo "5) Enable Tunnel"
    echo "6) Disable Tunnel"
    echo "7) Show logs"
    echo "8) Restart 9Router"
    echo "9) Uninstall completely"
    echo "0) Exit"
    read -r -p "Select: " choice
    case "$choice" in
      1) install_9router ;;
      2) update_9router ;;
      3) status_9router ;;
      4) tunnel_status ;;
      5) tunnel_request enable && echo "Tunnel enabled." || warn "Enable failed." ;;
      6) tunnel_request disable && echo "Tunnel disabled." || warn "Disable failed." ;;
      7) logs_9router ;;
      8) docker restart "$CONTAINER_NAME" ;;
      9) uninstall_9router ;;
      0) exit 0 ;;
      *) warn "Invalid option." ;;
    esac
  done
}

need_root
if [[ "${1:-}" == "install" ]]; then install_9router; else menu; fi
