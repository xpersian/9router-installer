#!/bin/bash
set -e

APP_NAME="9router"
IMAGE="decolua/9router:latest"
PORT="20128"
APP_DIR="/opt/9router"
DATA_DIR="/opt/9router/data"
ENV_FILE="/opt/9router/.env"
UPDATE_WRAPPER="/usr/local/sbin/9router-update"
SERVICE_FILE="/etc/systemd/system/9router-update.service"
TIMER_FILE="/etc/systemd/system/9router-update.timer"

die() { echo "ERROR: $*" >&2; exit 1; }
require_root() { [ "$EUID" -eq 0 ] || die "Run as root."; }

read_tty() {
  local prompt="$1" out="$2" value
  [ -r /dev/tty ] || die "Interactive terminal is required."
  read -r -p "$prompt" value </dev/tty
  printf -v "$out" '%s' "$value"
}

read_secret_tty() {
  local prompt="$1" out="$2" value
  [ -r /dev/tty ] || die "Interactive terminal is required for password input."
  read -r -s -p "$prompt" value </dev/tty
  echo
  printf -v "$out" '%s' "$value"
}

install_docker() {
  if command -v docker >/dev/null 2>&1; then
    systemctl enable --now docker >/dev/null 2>&1 || true
    return
  fi
  echo "Docker not found. Installing..."
  apt-get update
  apt-get install -y ca-certificates curl
  curl -fsSL https://get.docker.com | sh
  systemctl enable --now docker
}

detect_ipv4() {
  local ip
  ip=$(curl -4 -fsS --max-time 10 https://api.ipify.org || true)
  if ! echo "$ip" | grep -Eq '^[0-9]{1,3}(\.[0-9]{1,3}){3}$'; then
    ip=$(curl -4 -fsS --max-time 10 https://ipv4.icanhazip.com | tr -d '[:space:]' || true)
  fi
  echo "$ip" | grep -Eq '^[0-9]{1,3}(\.[0-9]{1,3}){3}$' || die "Could not detect public IPv4."
  printf '%s' "$ip"
}

configure_url() {
  local answer domain ip
  echo
  read_tty "Do you have a domain? (y/n): " answer
  if [[ "$answer" =~ ^[Yy]$ ]]; then
    read_tty "Enter domain (example.com): " domain
    domain=$(printf '%s' "$domain" | sed -E 's#^https?://##; s#/$##')
    [ -n "$domain" ] || die "Domain cannot be empty."
    BASE_URL="http://$domain:$PORT"
  else
    ip=$(detect_ipv4)
    BASE_URL="http://$ip:$PORT"
    echo "Detected IPv4: $ip"
  fi
  echo "Base URL: $BASE_URL"
}

new_password() {
  printf '9Router@%s' "$(openssl rand -hex 5)"
}

setup_password() {
  local p1 p2
  read_secret_tty "Dashboard password (Enter = auto-generate): " p1
  if [ -z "$p1" ]; then
    p1=$(new_password)
    PASSWORD_GENERATED="$p1"
    echo "Generated password: $p1"
  else
    [ "$(printf '%s' "$p1" | wc -c)" -ge 6 ] || die "Password must be at least 6 characters."
    read_secret_tty "Confirm password: " p2
    [ "$p1" = "$p2" ] || die "Passwords do not match."
  fi
  INITIAL_PASSWORD="$p1"
}

ensure_env() {
  mkdir -p "$APP_DIR" "$DATA_DIR"
  if [ ! -f "$ENV_FILE" ]; then
    configure_url
    setup_password
    cat > "$ENV_FILE" <<EOF
JWT_SECRET=$(openssl rand -hex 32)
INITIAL_PASSWORD=$INITIAL_PASSWORD
DATA_DIR=/app/data
PORT=$PORT
HOSTNAME=0.0.0.0
NODE_ENV=production
BASE_URL=$BASE_URL
CLOUD_URL=https://9router.com
NEXT_PUBLIC_BASE_URL=$BASE_URL
NEXT_PUBLIC_CLOUD_URL=https://9router.com
API_KEY_SECRET=$(openssl rand -hex 32)
MACHINE_ID_SALT=$(openssl rand -hex 32)
ENABLE_REQUEST_LOGS=false
AUTH_COOKIE_SECURE=false
REQUIRE_API_KEY=false
EOF
    chmod 600 "$ENV_FILE"
    if [ -n "$PASSWORD_GENERATED" ]; then
      echo "IMPORTANT: keep this dashboard password: $PASSWORD_GENERATED"
      echo "It will be preserved on future updates."
    fi
    return
  fi

  if ! grep -q '^INITIAL_PASSWORD=' "$ENV_FILE" || [ -z "$(grep -E '^INITIAL_PASSWORD=' "$ENV_FILE" | cut -d= -f2-)" ]; then
    setup_password
    sed -i '/^INITIAL_PASSWORD=/d' "$ENV_FILE"
    printf 'INITIAL_PASSWORD=%s\n' "$INITIAL_PASSWORD" >> "$ENV_FILE"
    echo "Dashboard password repaired and saved."
  else
    echo "Existing dashboard password preserved."
  fi
  chmod 600 "$ENV_FILE"
}

migrate_legacy_data() {
  if [ -f "/var/lib/9router/db/data.sqlite" ] && [ ! -f "$DATA_DIR/db/data.sqlite" ]; then
    echo "Migrating existing 9Router data from /var/lib/9router..."
    mkdir -p "$DATA_DIR"
    cp -a /var/lib/9router/. "$DATA_DIR/"
  fi
}

normalize_existing_env() {
  [ -f "$ENV_FILE" ] || return

  if grep -q '^DATA_DIR=' "$ENV_FILE"; then
    sed -i 's#^DATA_DIR=.*#DATA_DIR=/app/data#' "$ENV_FILE"
  else
    printf 'DATA_DIR=/app/data\n' >> "$ENV_FILE"
  fi

  if grep -q '^PORT=' "$ENV_FILE"; then
    sed -i 's#^PORT=.*#PORT=20128#' "$ENV_FILE"
  else
    printf 'PORT=20128\n' >> "$ENV_FILE"
  fi

  if grep -q '^HOSTNAME=' "$ENV_FILE"; then
    sed -i 's#^HOSTNAME=.*#HOSTNAME=0.0.0.0#' "$ENV_FILE"
  else
    printf 'HOSTNAME=0.0.0.0\n' >> "$ENV_FILE"
  fi

  if grep -q '^NODE_ENV=' "$ENV_FILE"; then
    sed -i 's#^NODE_ENV=.*#NODE_ENV=production#' "$ENV_FILE"
  else
    printf 'NODE_ENV=production\n' >> "$ENV_FILE"
  fi

  chmod 600 "$ENV_FILE"
}

migrate_legacy_data() {
  if [ -f "/var/lib/9router/db/data.sqlite" ] && [ ! -f "$DATA_DIR/db/data.sqlite" ]; then
    echo "Migrating existing data from /var/lib/9router..."
    mkdir -p "$DATA_DIR"
    cp -a /var/lib/9router/. "$DATA_DIR/"
  fi
}

normalize_existing_env() {
  [ -f "$ENV_FILE" ] || return

  if grep -q '^DATA_DIR=' "$ENV_FILE"; then
    sed -i 's#^DATA_DIR=.*#DATA_DIR=/app/data#' "$ENV_FILE"
  else
    printf 'DATA_DIR=/app/data\n' >> "$ENV_FILE"
  fi

  if grep -q '^PORT=' "$ENV_FILE"; then
    sed -i 's#^PORT=.*#PORT=20128#' "$ENV_FILE"
  else
    printf 'PORT=20128\n' >> "$ENV_FILE"
  fi

  if grep -q '^HOSTNAME=' "$ENV_FILE"; then
    sed -i 's#^HOSTNAME=.*#HOSTNAME=0.0.0.0#' "$ENV_FILE"
  else
    printf 'HOSTNAME=0.0.0.0\n' >> "$ENV_FILE"
  fi

  if grep -q '^NODE_ENV=' "$ENV_FILE"; then
    sed -i 's#^NODE_ENV=.*#NODE_ENV=production#' "$ENV_FILE"
  else
    printf 'NODE_ENV=production\n' >> "$ENV_FILE"
  fi

  chmod 600 "$ENV_FILE"
}

run_container() {
  docker rm -f "$APP_NAME" >/dev/null 2>&1 || true
  docker run -d \
    --name "$APP_NAME" \
    --restart unless-stopped \
    -p "0.0.0.0:$PORT:$PORT" \
    --env-file "$ENV_FILE" \
    -v "$DATA_DIR:/app/data" \
    "$IMAGE" >/dev/null
  echo "9Router container started."
}

container_exists() {
  docker container inspect "$APP_NAME" >/dev/null 2>&1
}

container_running() {
  [ "$(docker inspect -f '{{.State.Running}}' "$APP_NAME" 2>/dev/null || echo false)" = "true" ]
}

health_check() {
  local n
  for n in $(seq 1 60); do
    if curl -fsS --max-time 2 "http://127.0.0.1:$PORT/api/health" >/dev/null 2>&1; then
      echo "Health check: OK"
      return 0
    fi
    sleep 2
  done
  echo "WARNING: Health check failed."
  docker logs "$APP_NAME" --tail 50 || true
  return 1
}

check_firewall() {
  if command -v ufw >/dev/null 2>&1 || command -v firewall-cmd >/dev/null 2>&1 || command -v nft >/dev/null 2>&1; then
    echo "WARNING: A firewall tool is installed. No firewall rule was opened or changed."
  else
    echo "No common firewall tool detected."
  fi
}

install_or_update() {
  install_docker
  apt-get update
  apt-get install -y curl openssl ca-certificates
  ensure_env
  migrate_legacy_data
  normalize_existing_env

  local before after
  before=$(docker image inspect "$IMAGE" -f '{{.Id}}' 2>/dev/null || true)

  echo "Pulling latest 9Router image..."
  docker pull "$IMAGE" >/dev/null
  after=$(docker image inspect "$IMAGE" -f '{{.Id}}' 2>/dev/null || true)

  if ! container_exists; then
    run_container
  elif ! container_running; then
    echo "Starting existing stopped container..."
    docker start "$APP_NAME" >/dev/null
  elif [ "$before" != "$after" ]; then
    echo "New image detected. Recreating container..."
    run_container
  else
    echo "9Router is already up to date."
  fi

  health_check || true
  install_auto_update
  check_firewall
  show_status
}

update_now() {
  [ -f "$ENV_FILE" ] || die "9Router is not installed."
  install_docker
  mkdir -p "$APP_DIR" "$DATA_DIR"
  migrate_legacy_data
  normalize_existing_env

  local before after
  before=$(docker image inspect "$IMAGE" -f '{{.Id}}' 2>/dev/null || true)
  echo "Checking latest image..."
  docker pull "$IMAGE" >/dev/null
  after=$(docker image inspect "$IMAGE" -f '{{.Id}}' 2>/dev/null || true)

  if ! container_exists || ! container_running || [ "$before" != "$after" ]; then
    run_container
    health_check || true
  else
    echo "No new image. No restart needed."
  fi
  show_status
}

setup_update_wrapper() {
  cat > "$UPDATE_WRAPPER" <<'EOF'
#!/bin/bash
set -e
curl -fsSL https://github.com/xpersian/9router-installer/archive/refs/heads/main.tar.gz \
  | tar -xzO --wildcards '*/9router.sh' \
  | bash -s -- update
EOF
  chmod 755 "$UPDATE_WRAPPER"
}

install_auto_update() {
  setup_update_wrapper
  cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=Update 9Router Docker image
After=docker.service
Requires=docker.service

[Service]
Type=oneshot
ExecStart=$UPDATE_WRAPPER
EOF

  cat > "$TIMER_FILE" <<EOF
[Unit]
Description=Daily 9Router Docker image update

[Timer]
OnCalendar=*-*-* 04:30:00
RandomizedDelaySec=10m
Persistent=true
Unit=9router-update.service

[Install]
WantedBy=timers.target
EOF

  systemctl daemon-reload
  systemctl enable --now 9router-update.timer >/dev/null
}

cli_token() {
  local raw secret
  raw=$(cat "$DATA_DIR/machine-id" 2>/dev/null || true)
  secret=$(cat "$DATA_DIR/auth/cli-secret" 2>/dev/null || true)
  [ -n "$raw" ] && [ -n "$secret" ] || return 1
  printf '%s' "$raw"9r-cli-auth"$secret" | sha256sum | cut -c1-16
}

wait_for_cli_token() {
  local n token
  for n in $(seq 1 45); do
    token=$(cli_token || true)
    if [ -n "$token" ]; then
      printf '%s' "$token"
      return 0
    fi
    sleep 2
  done
  return 1
}

tunnel_request() {
  local method="$1" path="$2" token
  token=$(wait_for_cli_token) || die "Could not obtain 9Router CLI token. Check: docker logs $APP_NAME"
  curl -fsS --max-time 180 -X "$method" -H "x-9r-cli-token: $token" "http://127.0.0.1:$PORT$path"
}

tunnel_status() {
  echo
  echo "=== Tunnel status ==="
  container_running || { echo "9Router is not running."; return 1; }
  local response
  response=$(tunnel_request GET "/api/tunnel/status" || true)
  if command -v python3 >/dev/null 2>&1; then
    printf '%s\n' "$response" | python3 -m json.tool 2>/dev/null || printf '%s\n' "$response"
  else
    printf '%s\n' "$response"
  fi
}

enable_tunnel() {
  echo
  echo "=== Enable Tunnel ==="
  tunnel_request POST "/api/tunnel/enable"
  echo
  tunnel_status
}

disable_tunnel() {
  echo
  echo "=== Disable Tunnel ==="
  tunnel_request POST "/api/tunnel/disable"
}

refresh_tunnel() {
  disable_tunnel || true
  sleep 2
  enable_tunnel
}

show_status() {
  echo
  echo "=== 9Router status ==="
  docker ps -a --filter "name=^$APP_NAME$" --format 'table {{.Names}}\t{{.Status}}\t{{.Image}}'
  local base
  base=$(grep -E '^BASE_URL=' "$ENV_FILE" 2>/dev/null | cut -d= -f2- || true)
  [ -n "$base" ] || base="http://SERVER_IP:$PORT"
  echo "Dashboard: $base/dashboard"
  echo "API:       $base/v1"
  echo "Container restart policy: unless-stopped"
  echo "Auto-update timer: $(systemctl is-active 9router-update.timer 2>/dev/null || echo not-installed)"
}

show_logs() {
  docker logs --tail 150 -f "$APP_NAME"
}

restart_router() {
  docker restart "$APP_NAME" >/dev/null
  echo "9Router restarted."
  health_check || true
}

uninstall_router() {
  echo
  echo "=== Uninstall 9Router ==="
  echo "This permanently deletes the container, image, config and data:"
  echo "  $APP_DIR"
  echo "Docker itself remains installed."
  echo "No firewall rules will be changed."
  echo
  local answer
  read_tty "Type REMOVE to confirm: " answer
  [ "$answer" = "REMOVE" ] || { echo "Uninstall cancelled."; return; }

  systemctl disable --now 9router-update.timer >/dev/null 2>&1 || true
  rm -f "$SERVICE_FILE" "$TIMER_FILE" "$UPDATE_WRAPPER"
  systemctl daemon-reload
  docker rm -f "$APP_NAME" >/dev/null 2>&1 || true
  docker image rm "$IMAGE" >/dev/null 2>&1 || true
  rm -rf "$APP_DIR"
  echo "9Router removed. Docker was not removed."
}

menu() {
  while true; do
    echo
    echo "========================================"
    echo "          9Router Docker"
    echo "========================================"
    echo "1) Install / Update 9Router"
    echo "2) Update now"
    echo "3) Status"
    echo "4) Tunnel status"
    echo "5) Enable Tunnel"
    echo "6) Disable Tunnel"
    echo "7) Refresh Tunnel URL"
    echo "8) Show logs"
    echo "9) Restart 9Router"
    echo "10) Uninstall 9Router"
    echo "0) Exit"
    echo "========================================"

    local choice
    read_tty "Select an option [0-10]: " choice

    case "$choice" in
      1) install_or_update ;;
      2) update_now ;;
      3) show_status ;;
      4) tunnel_status ;;
      5) enable_tunnel ;;
      6) disable_tunnel ;;
      7) refresh_tunnel ;;
      8) show_logs ;;
      9) restart_router ;;
      10) uninstall_router ;;
      0) exit 0 ;;
      *) echo "Invalid option." ;;
    esac

    echo
    read_tty "Press Enter to return to the menu..." _
  done
}

require_root
MODE="$1"
[ -n "$MODE" ] || MODE="menu"

case "$MODE" in
  install) install_or_update ;;
  update) update_now ;;
  tunnel-status) tunnel_status ;;
  tunnel-enable) enable_tunnel ;;
  tunnel-disable) disable_tunnel ;;
  tunnel-refresh) refresh_tunnel ;;
  uninstall|remove|delete) uninstall_router ;;
  menu) menu ;;
  *) echo "Unknown command. Use: menu, install, update, tunnel-status, tunnel-enable, tunnel-disable, tunnel-refresh, uninstall." ;;
esac
