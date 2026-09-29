#!/bin/bash
set -e

NAME="9router"
IMAGE="decolua/9router:latest"
PORT="20128"
DIR="/opt/9router"
DATA="$DIR/data"
ENV="$DIR/.env"
UPDATE="/usr/local/sbin/9router-update"
SERVICE="/etc/systemd/system/9router-update.service"
TIMER="/etc/systemd/system/9router-update.timer"
RAW="https://github.com/xpersian/9router-installer/raw/refs/heads/main/9router.sh"

[ "$EUID" -eq 0 ] || { echo "Run as root."; exit 1; }

get_ipv4() {
  local ip
  ip=$(curl -4 -fsS --max-time 10 https://api.ipify.org 2>/dev/null || true)
  if [ -z "$ip" ]; then
    ip=$(curl -4 -fsS --max-time 10 https://ipv4.icanhazip.com 2>/dev/null | tr -d '[:space:]' || true)
  fi
  echo "$ip" | grep -Eq '^[0-9]{1,3}(\.[0-9]{1,3}){3}$' || { echo "Could not detect public IPv4."; exit 1; }
  printf '%s' "$ip"
}

setup_password() {
  local pass
  if [ -f "$ENV" ] && grep -q '^INITIAL_PASSWORD=' "$ENV"; then
    pass=$(grep '^INITIAL_PASSWORD=' "$ENV" | head -n1 | cut -d= -f2-)
    if [ -n "$pass" ]; then
      PASSWORD_STATUS="Existing dashboard password preserved."
      return
    fi
  fi

  read -r -s -p "Dashboard password (Enter = generate): " pass </dev/tty
  echo

  if [ -z "$pass" ]; then
    pass="9Router@$(openssl rand -hex 5)"
    PASSWORD_STATUS="Generated dashboard password: $pass"
    echo "Generated dashboard password: $pass"
  else
    [ "$(printf '%s' "$pass" | wc -c)" -ge 6 ] || { echo "Password must be at least 6 characters."; exit 1; }
    PASSWORD_STATUS="Dashboard password set by you."
  fi

  sed -i '/^INITIAL_PASSWORD=/d' "$ENV" 2>/dev/null || true
  printf 'INITIAL_PASSWORD=%s\n' "$pass" >> "$ENV"
}

prepare_env() {
  mkdir -p "$DIR" "$DATA"

  if [ ! -f "$ENV" ]; then
    local ip
    ip=$(get_ipv4)

    cat > "$ENV" <<EOF
JWT_SECRET=$(openssl rand -hex 32)
INITIAL_PASSWORD=
DATA_DIR=/app/data
PORT=20128
HOSTNAME=0.0.0.0
NODE_ENV=production
BASE_URL=http://$ip:20128
NEXT_PUBLIC_BASE_URL=http://$ip:20128
CLOUD_URL=https://9router.com
NEXT_PUBLIC_CLOUD_URL=https://9router.com
API_KEY_SECRET=$(openssl rand -hex 32)
MACHINE_ID_SALT=$(openssl rand -hex 32)
ENABLE_REQUEST_LOGS=false
AUTH_COOKIE_SECURE=false
REQUIRE_API_KEY=false
EOF
  fi

  setup_password
  chmod 600 "$ENV"
}

install_docker() {
  if command -v docker >/dev/null 2>&1; then
    systemctl enable --now docker >/dev/null 2>&1 || true
    return
  fi

  echo "Installing Docker..."
  apt-get update
  apt-get install -y ca-certificates curl openssl
  curl -fsSL https://get.docker.com | sh
  systemctl enable --now docker
}

start_router() {
  docker rm -f "$NAME" >/dev/null 2>&1 || true
  docker run -d \
    --name "$NAME" \
    --restart unless-stopped \
    -p "0.0.0.0:$PORT:$PORT" \
    --env-file "$ENV" \
    -v "$DATA:/app/data" \
    "$IMAGE" >/dev/null
}

install_timer() {
  printf '%s\n' \
    '#!/bin/bash' \
    'set -e' \
    "curl -fsSL $RAW | bash -s -- update" \
    > "$UPDATE"
  chmod 755 "$UPDATE"

  printf '%s\n' \
    '[Unit]' \
    'Description=9Router automatic update' \
    'After=docker.service' \
    'Requires=docker.service' \
    '' \
    '[Service]' \
    'Type=oneshot' \
    "ExecStart=$UPDATE" \
    > "$SERVICE"

  printf '%s\n' \
    '[Unit]' \
    'Description=Daily 9Router update' \
    '' \
    '[Timer]' \
    'OnCalendar=*-*-* 04:30:00' \
    'RandomizedDelaySec=10m' \
    'Persistent=true' \
    'Unit=9router-update.service' \
    '' \
    '[Install]' \
    'WantedBy=timers.target' \
    > "$TIMER"

  systemctl daemon-reload
  systemctl enable --now 9router-update.timer >/dev/null
}

firewall_warning() {
  if command -v ufw >/dev/null 2>&1 || command -v firewall-cmd >/dev/null 2>&1 || command -v nft >/dev/null 2>&1; then
    echo "WARNING: Firewall is installed. No firewall rules were changed."
  fi
}

install_router() {
  install_docker
  prepare_env
  echo "Pulling $IMAGE..."
  docker pull "$IMAGE" >/dev/null
  start_router
  install_timer
  firewall_warning

  local ip
  ip=$(get_ipv4)

  echo
  echo "9Router is running."
  echo "Dashboard: http://$ip:$PORT/dashboard"
  echo "API:       http://$ip:$PORT/v1"
  echo "$PASSWORD_STATUS"
}

update_router() {
  install_docker
  [ -f "$ENV" ] || { echo "9Router is not installed."; exit 1; }

  local before after
  before=$(docker image inspect "$IMAGE" -f '{{.Id}}' 2>/dev/null || true)

  echo "Checking for updates..."
  docker pull "$IMAGE" >/dev/null

  after=$(docker image inspect "$IMAGE" -f '{{.Id}}' 2>/dev/null || true)

  if [ "$before" != "$after" ]; then
    start_router
    echo "9Router updated."
  else
    echo "9Router is already up to date."
  fi

  install_timer
}

status_router() {
  docker ps -a --filter "name=^$NAME$" --format 'table {{.Names}}\t{{.Status}}\t{{.Image}}'
  echo
  local ip
  ip=$(get_ipv4)
  echo "Dashboard: http://$ip:$PORT/dashboard"
  echo "Auto-update: $(systemctl is-active 9router-update.timer 2>/dev/null || echo inactive)"
}

restart_router() {
  docker restart "$NAME" >/dev/null
  echo "9Router restarted."
}

uninstall_router() {
  local answer
  echo "This removes 9Router, its configuration and data."
  read -r -p "Type REMOVE to confirm: " answer </dev/tty
  [ "$answer" = "REMOVE" ] || { echo "Cancelled."; return; }

  systemctl disable --now 9router-update.timer >/dev/null 2>&1 || true
  rm -f "$SERVICE" "$TIMER" "$UPDATE"
  systemctl daemon-reload
  docker rm -f "$NAME" >/dev/null 2>&1 || true
  docker image rm "$IMAGE" >/dev/null 2>&1 || true
  rm -rf "$DIR"

  echo "9Router removed. Docker was not removed."
}

menu() {
  while true; do
    echo
    echo "1) Install / Update 9Router"
    echo "2) Status"
    echo "3) Restart 9Router"
    echo "4) Uninstall 9Router"
    echo "0) Exit"
    local choice
    read -r -p "Select an option [0-4]: " choice </dev/tty

    if [ "$choice" = "1" ]; then
      install_router
    elif [ "$choice" = "2" ]; then
      status_router
    elif [ "$choice" = "3" ]; then
      restart_router
    elif [ "$choice" = "4" ]; then
      uninstall_router
    elif [ "$choice" = "0" ]; then
      exit 0
    else
      echo "Invalid option."
    fi
  done
}

if [ "$#" -eq 0 ]; then
  menu
elif [ "$1" = "install" ]; then
  install_router
elif [ "$1" = "update" ]; then
  update_router
elif [ "$1" = "status" ]; then
  status_router
elif [ "$1" = "restart" ]; then
  restart_router
elif [ "$1" = "uninstall" ] || [ "$1" = "remove" ] || [ "$1" = "delete" ]; then
  uninstall_router
else
  echo "Usage: $0 [install|update|status|restart|uninstall]"
  exit 1
fi
