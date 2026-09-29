#!/bin/bash
set -e

APP_DIR="/opt/9router"
DATA_DIR="/var/lib/9router"
APP_NAME="9router"
PORT="20128"
REPO="https://github.com/decolua/9router.git"

die() {
  echo "ERROR: $*" >&2
  exit 1
}

read_tty() {
  local prompt="$1" var="$2" value
  [ -r /dev/tty ] || die "Interactive terminal is required."
  read -r -p "$prompt" value </dev/tty
  printf -v "$var" "%s" "$value"
}

read_secret_tty() {
  local prompt="$1" var="$2" value
  [ -r /dev/tty ] || die "Interactive terminal is required for password setup."
  read -r -s -p "$prompt" value </dev/tty
  echo
  printf -v "$var" "%s" "$value"
}

install_deps() {
  apt update
  apt install -y git curl build-essential openssl

  if ! command -v node >/dev/null 2>&1; then
    curl -fsSL https://deb.nodesource.com/setup_22.x | bash -
    apt install -y nodejs
  fi

  if ! command -v pm2 >/dev/null 2>&1; then
    npm install -g pm2
  fi
}

detect_ipv4() {
  local ip
  ip=$(curl -4 -fsS --max-time 10 https://api.ipify.org 2>/dev/null || true)
  if [ -z "$ip" ]; then
    ip=$(curl -4 -fsS --max-time 10 https://ipv4.icanhazip.com 2>/dev/null | tr -d '[:space:]' || true)
  fi
  [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || die "Could not detect public IPv4."
  printf "%s" "$ip"
}

configure_url() {
  local answer domain ip
  read_tty "Do you have a domain? (y/n): " answer

  if [[ "$answer" =~ ^[Yy]$ ]]; then
    read_tty "Enter domain (example.com): " domain
    domain="${domain#http://}"
    domain="${domain#https://}"
    domain="${domain%/}"
    [ -n "$domain" ] || die "Domain cannot be empty."
    BASE_URL="http://$domain:$PORT"
  else
    ip=$(detect_ipv4)
    BASE_URL="http://$ip:$PORT"
    echo "Detected IPv4: $ip"
  fi

  echo "Base URL: $BASE_URL"
}

prompt_password() {
  local p1 p2
  PASSWORD_STATUS=""
  read_secret_tty "Choose dashboard password (Enter = generate): " p1

  if [ -z "$p1" ]; then
    p1="9Router@$(openssl rand -hex 5)"
    PASSWORD_STATUS="Generated dashboard password: $p1"
    echo
    echo "Generated dashboard password: $p1"
  else
    [ "${#p1}" -ge 6 ] || die "Password must be at least 6 characters."
    case "$p1" in *[[:space:]]*) die "Password must not contain spaces.";; esac
    read_secret_tty "Confirm dashboard password: " p2
    [ "$p1" = "$p2" ] || die "Passwords do not match."
    PASSWORD_STATUS="Dashboard password was set by you."
  fi

  INITIAL_PASSWORD="$p1"
}

configure_env() {
  mkdir -p "$DATA_DIR"

  if [ ! -f "$APP_DIR/.env" ]; then
    configure_url
    prompt_password

    cat > "$APP_DIR/.env" <<EOF
JWT_SECRET=$(openssl rand -hex 32)
INITIAL_PASSWORD=$INITIAL_PASSWORD
DATA_DIR=$DATA_DIR
PORT=$PORT
HOSTNAME=0.0.0.0
NODE_ENV=production
BASE_URL=$BASE_URL
NEXT_PUBLIC_BASE_URL=$BASE_URL
CLOUD_URL=https://9router.com
NEXT_PUBLIC_CLOUD_URL=https://9router.com
API_KEY_SECRET=$(openssl rand -hex 32)
MACHINE_ID_SALT=$(openssl rand -hex 32)
EOF
    chmod 600 "$APP_DIR/.env"
    return
  fi

  local existing_password
  existing_password=$(grep -E '^INITIAL_PASSWORD=' "$APP_DIR/.env" | head -n1 | cut -d= -f2- || true)

  if [ -z "$existing_password" ]; then
    echo "Existing installation has no dashboard password."
    prompt_password
    sed -i '/^INITIAL_PASSWORD=/d' "$APP_DIR/.env"
    printf 'INITIAL_PASSWORD=%s\n' "$INITIAL_PASSWORD" >> "$APP_DIR/.env"
  else
    PASSWORD_STATUS="Existing dashboard password preserved."
  fi

  if ! grep -q '^BASE_URL=' "$APP_DIR/.env"; then
    local url
    url=$(grep -E '^NEXT_PUBLIC_BASE_URL=' "$APP_DIR/.env" | head -n1 | cut -d= -f2- || true)
    [ -n "$url" ] || { url="http://$(detect_ipv4):$PORT"; }
    printf 'BASE_URL=%s\n' "$url" >> "$APP_DIR/.env"
  fi

  if ! grep -q '^CLOUD_URL=' "$APP_DIR/.env"; then
    printf 'CLOUD_URL=https://9router.com\n' >> "$APP_DIR/.env"
  fi

  if ! grep -q '^NEXT_PUBLIC_CLOUD_URL=' "$APP_DIR/.env"; then
    printf 'NEXT_PUBLIC_CLOUD_URL=https://9router.com\n' >> "$APP_DIR/.env"
  fi

  chmod 600 "$APP_DIR/.env"
}

prepare_build_swap() {
  BUILD_SWAP="/swapfile_9router_build"
  BUILD_SWAP_CREATED="false"

  local total_swap
  total_swap=$(swapon --show=SIZE --noheadings --bytes 2>/dev/null | awk '{s+=$1} END {print s+0}')
  total_swap=${total_swap:-0}

  if [ "$total_swap" -lt 2147483648 ]; then
    echo "Less than 2 GiB swap detected; creating temporary 2 GiB build swap..."
    if [ ! -e "$BUILD_SWAP" ]; then
      fallocate -l 2G "$BUILD_SWAP"
      chmod 600 "$BUILD_SWAP"
      mkswap "$BUILD_SWAP" >/dev/null
    fi
    swapon "$BUILD_SWAP"
    BUILD_SWAP_CREATED="true"
  fi
}

cleanup_build_swap() {
  if [ "$BUILD_SWAP_CREATED" = "true" ]; then
    swapoff "$BUILD_SWAP" 2>/dev/null || true
    rm -f "$BUILD_SWAP"
  fi
}

ensure_source() {
  if [ -d "$APP_DIR/.git" ]; then
    cd "$APP_DIR"
    git remote set-url origin "$REPO" 2>/dev/null || true
    git fetch --depth 1 origin
    git reset --hard origin/HEAD
    git clean -fdx -e .env
    return
  fi

  local backup=""
  if [ -f "$APP_DIR/.env" ]; then
    backup="/tmp/9router.env.backup.$$"
    cp -p "$APP_DIR/.env" "$backup"
  fi

  rm -rf "$APP_DIR"
  git clone --depth 1 "$REPO" "$APP_DIR"

  if [ -n "$backup" ] && [ -f "$backup" ]; then
    cp -p "$backup" "$APP_DIR/.env"
    rm -f "$backup"
  fi
}

install_app() {
  ensure_source
  cd "$APP_DIR"

  echo "Installing npm dependencies..."
  npm install --omit=optional --no-audit --no-fund --progress=false --fetch-retries=2 --fetch-timeout=60000

  echo "Building 9router..."
  MAKEFLAGS="-j1" NODE_OPTIONS="--max-old-space-size=768" npm run build

  pm2 delete "$APP_NAME" 2>/dev/null || true
  pm2 start custom-server.js --name "$APP_NAME" -- --port "$PORT"
  pm2 save
  pm2 startup systemd -u root --hp /root >/dev/null 2>&1 || true
}

check_firewall() {
  if command -v ufw >/dev/null 2>&1 || command -v firewall-cmd >/dev/null 2>&1 || command -v nft >/dev/null 2>&1; then
    echo "WARNING: A firewall tool is installed. No firewall rules will be changed."
  else
    echo "No common firewall tool detected. No firewall changes made."
  fi
}

verify() {
  if ss -lntp 2>/dev/null | grep -q ":$PORT "; then
    echo "Listening: TCP $PORT"
  else
    echo "WARNING: Nothing is listening on TCP $PORT."
  fi

  if curl -fsS --max-time 10 "http://127.0.0.1:$PORT/dashboard" >/dev/null 2>&1; then
    echo "Local dashboard check: OK"
  else
    echo "WARNING: Local dashboard check failed."
  fi
}

run_install() {
  install_deps
  mkdir -p "$APP_DIR"
  configure_env
  prepare_build_swap
  trap cleanup_build_swap EXIT
  install_app
  cleanup_build_swap
  trap - EXIT
  check_firewall
  verify

  echo
  echo "========================================"
  echo "9router installed/updated successfully"
  echo "========================================"
  echo "Dashboard: $(grep -E '^BASE_URL=' "$APP_DIR/.env" | cut -d= -f2-)/dashboard"
  echo "$PASSWORD_STATUS"
  echo "========================================"
}

show_status() {
  echo "=== 9router status ==="
  pm2 status "$APP_NAME" 2>/dev/null || pm2 status
  echo
  ss -lntp 2>/dev/null | grep ":$PORT " || echo "Nothing is listening on TCP $PORT."
}

show_logs() {
  pm2 logs "$APP_NAME" --lines 100 --nostream
}

restart_app() {
  pm2 restart "$APP_NAME"
  pm2 save
}

uninstall() {
  echo
  echo "This will permanently remove:"
  echo "  $APP_DIR"
  echo "  $DATA_DIR"
  echo
  echo "Node.js, npm, PM2 and Git will NOT be removed."
  echo "Firewall rules will NOT be changed."
  echo
  local answer
  read_tty "Type REMOVE to confirm: " answer
  [ "$answer" = "REMOVE" ] || { echo "Uninstall cancelled."; return; }

  pm2 delete "$APP_NAME" 2>/dev/null || true
  pm2 save >/dev/null 2>&1 || true
  rm -rf "$APP_DIR" "$DATA_DIR"

  if [ -e "/swapfile_9router_build" ]; then
    swapoff "/swapfile_9router_build" 2>/dev/null || true
    rm -f "/swapfile_9router_build"
  fi

  echo "9router has been removed."
}

menu() {
  while true; do
    echo
    echo "========================================"
    echo "           9router Installer"
    echo "========================================"
    echo "1) Install / Update 9Router"
    echo "2) Status"
    echo "3) Show logs"
    echo "4) Restart 9Router"
    echo "5) Uninstall 9Router"
    echo "0) Exit"
    echo "========================================"

    local choice
    read_tty "Select an option [0-5]: " choice

    case "$choice" in
      1) run_install ;;
      2) show_status ;;
      3) show_logs ;;
      4) restart_app ;;
      5) uninstall ;;
      0) exit 0 ;;
      *) echo "Invalid option." ;;
    esac
  done
}

case "${1:-menu}" in
  menu) menu ;;
  install|update) run_install ;;
  uninstall|remove|delete) uninstall ;;
  *) echo "Usage: $0 [install|update|uninstall|menu]" ;;
esac
