#!/bin/bash
set -e

NAME="9router"
IMAGE="decolua/9router:latest"
PORT="20128"
DIR="/opt/9router"
DATA_DIR="$DIR/data"
ENV_FILE="$DIR/.env"
UPDATE="/usr/local/sbin/9router-update"
SERVICE="/etc/systemd/system/9router-update.service"
TIMER="/etc/systemd/system/9router-update.timer"
RAW_URL="https://github.com/xpersian/9router-installer/raw/refs/heads/main/9router.sh"

[ "$EUID" -eq 0 ] || { echo "Run as root."; exit 1; }

ipv4() {
  local ip
  ip=$(curl -4 -fsS --max-time 10 https://api.ipify.org 2>/dev/null || true)
  [ -n "$ip" ] || ip=$(curl -4 -fsS --max-time 10 https://ipv4.icanhazip.com 2>/dev/null | tr -d "[:space:]" || true)
  echo "$ip" | grep -Eq "^[0-9]{1,3}(\.[0-9]{1,3}){3}$" || { echo "Could not detect public IPv4." >&2; exit 1; }
  printf "%s" "$ip"
}

read_tty() {
  local prompt="$1" var="$2" value
  read -r -p "$prompt" value </dev/tty
  printf -v "$var" "%s" "$value"
}

setup_password() {
  local pass
  if [ -f "$ENV_FILE" ] && grep -q "^INITIAL_PASSWORD=" "$ENV_FILE" && [ -n "$(grep "^INITIAL_PASSWORD=" "$ENV_FILE" | head -n1 | cut -d= -f2-)" ]; then
    PASSWORD_STATUS="Existing dashboard password preserved."
    return
  fi
  read -r -s -p "Dashboard password (Enter = generate): " pass </dev/tty
  echo
  if [ -z "$pass" ]; then
    pass="9Router@$(openssl rand -hex 5)"
    echo "Generated dashboard password: $pass"
    PASSWORD_STATUS="Generated dashboard password: $pass"
  else
    [ "$(printf "%s" "$pass" | wc -c)" -ge 6 ] || { echo "Password must be at least 6 characters."; exit 1; }
    PASSWORD_STATUS="Dashboard password was set by you."
  fi
  sed -i "/^INITIAL_PASSWORD=/d" "$ENV_FILE" 2>/dev/null || true
  printf "INITIAL_PASSWORD=%s\n" "$pass" >> "$ENV_FILE"
}

create_env() {
  mkdir -p "$DIR" "$DATA_DIR"
  if [ ! -f "$ENV_FILE" ]; then
    local ip
    ip=$(ipv4)
    cat > "$ENV_FILE" <<EOF
JWT_SECRET=$(openssl rand -hex 32)
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
INITIAL_PASSWORD=
EOF
    chmod 600 "$ENV_FILE"
  fi
  setup_password
  chmod 600 "$ENV_FILE"
}

docker_install() {
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

run_container() {
  docker rm -f "$NAME" >/dev/null 2>&1 || true
  docker run -d \
    --name "$NAME" \
    --restart unless-stopped \
    -p "0.0.0.0:$PORT:$PORT" \
    --env-file "$ENV_FILE" \
    -v "$DATA_DIR:/app/data" \
    "$IMAGE" >/dev/null
}

update_timer() {
  cat > "$UPDATE" <<EOF
#!/bin/bash
set -e
curl -fsSL https://github.com/xpersian/9router-installer/raw/refs/heads/main/9router.sh | bash -s -- update
EOF
  chmod 755 "$UPDATE"
  cat > "$SERVICE" <<EOF
[Unit]
Description=9Router automatic update
After=docker.service
Requires=docker.service

[Service]
Type=oneshot
ExecStart=$UPDATE
EOF
  cat > "$TIMER" <<EOF
[Unit]
Description=Daily 9Router update

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

firewall_check() {
  if command -v ufw >/dev/null 2>&1 || command -v firewall-cmd >/dev/null 2>&1 || command -v nft >/dev/null 2>&1; then
    echo "WARNING: Firewall is installed. No firewall rules were changed."
  fi
}

install_router() {
  docker_install
  create_env
  echo "Pulling $IMAGE..."
  docker pull "$IMAGE" >/dev/null
  run_container
  update_timer
  firewall_check
  local ip
  ip=$(ipv4)
  echo
  echo "9Router is running."
  echo "Dashboard: http://$ip:$PORT/dashboard"
  echo "API:       http://$ip:$PORT/v1"
  echo "$PASSWORD_STATUS"
}

update_router() {
  docker_install
  [ -f "$ENV_FILE" ] || { echo "9Router is not installed."; exit 1; }
  local before after
  before=$(docker image inspect "$IMAGE" -f "{{.Id}}" 2>/dev/null || true)
  echo "Checking for updates..."
  docker pull "$IMAGE" >/dev/null
  after=$(docker image inspect "$IMAGE" -f "{{.Id}}" 2>/dev/null || true)
  if [ "$before" != "$after" ]; then
    run_container
    echo "9Router updated."
  else
    echo "9Router is already up to date."
  fi
  update_timer
}

status_router() {
  docker ps -a --filter "name=^$NAME$" --format "table {{.Names}}\t{{.Status}}\t{{.Image}}"
  local ip
  ip=$(ipv4)
  echo
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
  read_tty "Type REMOVE to confirm: " answer
  [ "$answer" = "REMOVE" ] || { echo "Cancelled."; exit 0; }
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
    read_tty "Select an option [0-4]: " choice
    case "$choice" in
      1) install_router ;;
      2) status_router ;;
      3) restart_router ;;
      4) uninstall_router ;;
      0) exit 0 ;;
      *) echo "Invalid option." ;;
    esac
  done
}

case "${1:-menu}" in
  menu) menu ;;
  install|update) [ "$1" = "update" ] && update_router || install_router ;;
  status) status_router ;;
  restart) restart_router ;;
  uninstall|remove|delete) uninstall_router ;;
  *) echo "Usage: $0 [install|update|status|restart|uninstall|menu]"; exit 1 ;;
esac
