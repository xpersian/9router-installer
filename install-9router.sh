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
  local prompt="$1"
  local __var="$2"
  local value
  [ -r /dev/tty ] || die "Interactive terminal (/dev/tty) is required for first-time setup."
  read -r -p "$prompt" value </dev/tty
  printf -v "$__var" '%s' "$value"
}

read_secret_tty() {
  local prompt="$1"
  local __var="$2"
  local value
  [ -r /dev/tty ] || die "Interactive terminal (/dev/tty) is required for password setup."
  read -r -s -p "$prompt" value </dev/tty
  echo
  printf -v "$__var" '%s' "$value"
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
  ip=$(curl -4 -fsS --max-time 10 https://api.ipify.org || true)

  if [[ ! "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
    ip=$(curl -4 -fsS --max-time 10 https://ipv4.icanhazip.com | tr -d '[:space:]' || true)
  fi

  [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || die "Could not detect the server IPv4 address."
  printf '%s' "$ip"
}

configure_url() {
  local has_domain domain server_ip

  echo
  echo "=== 9router URL configuration ==="
  read_tty "Do you have a domain? (y/n): " has_domain

  if [[ "$has_domain" =~ ^[Yy]$ ]]; then
    read_tty "Enter your domain (example.com): " domain
    domain="\${domain#http://}"
    domain="\${domain#https://}"
    domain="\${domain%/}"
    [ -n "$domain" ] || die "Domain cannot be empty."

    BASE_URL="http://$domain:$PORT"

    echo "Direct URL: $BASE_URL"
    echo "This installer does not configure TLS/reverse proxy."
  else
    server_ip=$(detect_ipv4)
    BASE_URL="http://$server_ip:$PORT"

    echo "Detected IPv4: $server_ip"
    echo "Direct URL: $BASE_URL"
  fi
}

prompt_password() {
  local p1 p2
  PASSWORD_WAS_GENERATED="false"
  PASSWORD_GENERATED_VALUE=""

  while true; do
    read_secret_tty "Choose dashboard password (press Enter for auto-generated password): " p1

    if [ -z "$p1" ]; then
      p1="9Router@$(openssl rand -hex 5)"
      PASSWORD_WAS_GENERATED="true"
      PASSWORD_GENERATED_VALUE="$p1"
      echo "No password entered. Generated password: $p1"
      break
    fi

    [ "\${#p1}" -ge 6 ] || { echo "Password must be at least 6 characters."; continue; }
    [[ "$p1" != *[[:space:]]* ]] || { echo "Password must not contain spaces or tabs."; continue; }

    read_secret_tty "Confirm dashboard password: " p2

    if [ "$p1" = "$p2" ]; then
      break
    fi

    echo "Passwords do not match. Try again."
  done

  INITIAL_PASSWORD="$p1"
}

repair_existing_env() {
  local existing_password old_public_url host_part server_ip

  existing_password=$(grep -E '^INITIAL_PASSWORD=' "$APP_DIR/.env" | head -n1 | cut -d= -f2- || true)

  if [ -z "$existing_password" ]; then
    echo
    echo "No dashboard password is stored in the existing configuration."
    prompt_password

    sed -i '/^INITIAL_PASSWORD=/d' "$APP_DIR/.env"
    printf 'INITIAL_PASSWORD=%s\n' "$INITIAL_PASSWORD" >> "$APP_DIR/.env"

    if [ "$PASSWORD_WAS_GENERATED" = "true" ]; then
      echo "Keep this password safe. It will be preserved on future updates."
    fi
  else
    PASSWORD_STATUS="Existing dashboard password preserved."
  fi

  old_public_url=$(grep -E '^NEXT_PUBLIC_BASE_URL=' "$APP_DIR/.env" | head -n1 | cut -d= -f2- || true)

  if [ -z "$old_public_url" ]; then
    server_ip=$(detect_ipv4)
    old_public_url="http://$server_ip:$PORT"
    printf 'NEXT_PUBLIC_BASE_URL=%s\n' "$old_public_url" >> "$APP_DIR/.env"
  else
    host_part="$old_public_url"
    host_part="\${host_part#http://}"
    host_part="\${host_part#https://}"

    if [[ "$host_part" == *:*:* ]]; then
      server_ip=$(detect_ipv4)
      old_public_url="http://$server_ip:$PORT"
      sed -i '/^NEXT_PUBLIC_BASE_URL=/d' "$APP_DIR/.env"
      printf 'NEXT_PUBLIC_BASE_URL=%s\n' "$old_public_url" >> "$APP_DIR/.env"
      echo "Repaired invalid IPv6 public URL: $old_public_url"
    fi
  fi

  if ! grep -q '^BASE_URL=' "$APP_DIR/.env"; then
    printf 'BASE_URL=%s\n' "$old_public_url" >> "$APP_DIR/.env"
  fi

  if ! grep -q '^CLOUD_URL=' "$APP_DIR/.env"; then
    printf 'CLOUD_URL=https://9router.com\n' >> "$APP_DIR/.env"
  fi

  if ! grep -q '^NEXT_PUBLIC_CLOUD_URL=' "$APP_DIR/.env"; then
    printf 'NEXT_PUBLIC_CLOUD_URL=https://9router.com\n' >> "$APP_DIR/.env"
  fi

  chmod 600 "$APP_DIR/.env"
}

create_or_update_env() {
  mkdir -p "$DATA_DIR"
  PASSWORD_STATUS=""

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
CLOUD_URL=https://9router.com
NEXT_PUBLIC_BASE_URL=$BASE_URL
NEXT_PUBLIC_CLOUD_URL=https://9router.com
API_KEY_SECRET=$(openssl rand -hex 32)
MACHINE_ID_SALT=$(openssl rand -hex 32)
ENABLE_REQUEST_LOGS=false
AUTH_COOKIE_SECURE=false
REQUIRE_API_KEY=false
EOF

    chmod 600 "$APP_DIR/.env"

    if [ "$PASSWORD_WAS_GENERATED" = "true" ]; then
      PASSWORD_STATUS="Generated dashboard password: $PASSWORD_GENERATED_VALUE"
      echo
      echo "IMPORTANT: Your generated dashboard password is:"
      echo "$PASSWORD_GENERATED_VALUE"
      echo "It will be preserved on future updates."
    else
      PASSWORD_STATUS="Dashboard password was set by you and will be preserved on future updates."
    fi
  else
    repair_existing_env
  fi
}

prepare_build_swap() {
  BUILD_SWAP="/swapfile_9router_build"
  BUILD_SWAP_CREATED="false"

  local total_swap
  total_swap=$(swapon --show=SIZE --noheadings --bytes 2>/dev/null | awk '{s+=$1} END {print s+0}')

  if [ "\${total_swap:-0}" -lt 2147483648 ]; then
    echo "Less than 2 GiB swap detected. Creating temporary 2 GiB build swap..."

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
  if [ "$BUILD_SWAP_CREATED" = "true" ] &&
     swapon --show=NAME --noheadings 2>/dev/null | grep -qx "$BUILD_SWAP"; then
    swapoff "$BUILD_SWAP" || true
    rm -f "$BUILD_SWAP"
  fi
}

ensure_repo() {
  if [ -d "$APP_DIR/.git" ]; then
    cd "$APP_DIR"
    git remote set-url origin "$REPO" 2>/dev/null || git remote add origin "$REPO"
    git fetch --prune origin

    local default_branch
    default_branch=$(git remote show origin 2>/dev/null | sed -n '/HEAD branch/s/.*: //p')
    [ -n "$default_branch" ] || default_branch="main"

    git reset --hard "origin/$default_branch"
    return
  fi

  if [ -d "$APP_DIR" ] && [ -n "$(find "$APP_DIR" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null)" ]; then
    echo "Existing 9router directory found without Git metadata."
    echo "Refreshing the source while preserving .env..."

    local env_backup="/tmp/9router.env.backup"
    rm -f "$env_backup"

    if [ -f "$APP_DIR/.env" ]; then
      cp -p "$APP_DIR/.env" "$env_backup"
    fi

    rm -rf "$APP_DIR"
    git clone "$REPO" "$APP_DIR"

    if [ -f "$env_backup" ]; then
      cp -p "$env_backup" "$APP_DIR/.env"
      rm -f "$env_backup"
    fi

    return
  fi

  rm -rf "$APP_DIR"
  git clone "$REPO" "$APP_DIR"
}

install_app() {
  ensure_repo
  cd "$APP_DIR"

  prepare_build_swap
  trap cleanup_build_swap EXIT

  npm install

  echo "Building 9router..."
  MAKEFLAGS="-j1" NODE_OPTIONS="--max-old-space-size=768" npm run build

  cleanup_build_swap
  trap - EXIT

  pm2 delete "$APP_NAME" 2>/dev/null || true
  pm2 start npm --name "$APP_NAME" -- start
  pm2 save
  pm2 startup systemd -u root --hp /root >/dev/null 2>&1 || true
}

check_firewall() {
  if command -v ufw >/dev/null 2>&1 || command -v firewall-cmd >/dev/null 2>&1 || command -v nft >/dev/null 2>&1; then
    echo
    echo "WARNING: A firewall component appears to be installed."
    echo "The installer will NOT open or modify any firewall port."
  else
    echo "No common firewall tool detected. No firewall changes were made."
  fi
}

verify_service() {
  echo
  echo "=== Verifying 9router ==="

  if ss -lntp | grep -q ":$PORT "; then
    echo "Listening: TCP $PORT"
  else
    echo "WARNING: Nothing is listening on TCP $PORT."
    pm2 status || true
    pm2 logs "$APP_NAME" --lines 30 --nostream || true
    return 1
  fi

  if curl -fsS --max-time 10 "http://127.0.0.1:$PORT/dashboard" >/dev/null; then
    echo "Local dashboard check: OK"
  else
    echo "WARNING: Local dashboard check failed."
    pm2 logs "$APP_NAME" --lines 30 --nostream || true
    return 1
  fi
}

show_result() {
  local url
  url=$(grep -E '^BASE_URL=' "$APP_DIR/.env" | head -n1 | cut -d= -f2- || true)

  echo
  echo "========================================"
  echo "9router installed/updated successfully"
  echo "========================================"
  echo "Dashboard: \${url:-http://SERVER_IP:$PORT}/dashboard"
  echo "API:       \${url:-http://SERVER_IP:$PORT}/v1"
  echo "$PASSWORD_STATUS"
  echo
  echo "Status: pm2 status"
  echo "Logs:   pm2 logs $APP_NAME"
  echo "========================================"
}

uninstall() {
  echo
  echo "=== Remove 9router ==="
  echo "This will stop 9router and permanently delete:"
  echo "  $APP_DIR"
  echo "  $DATA_DIR"
  echo
  echo "PM2 itself will NOT be removed."
  echo "No firewall rules will be changed."
  echo

  local answer
  read_tty "Type REMOVE to confirm: " answer

  [ "$answer" = "REMOVE" ] || {
    echo "Uninstall cancelled."
    exit 0
  }

  pm2 delete "$APP_NAME" 2>/dev/null || true
  pm2 save >/dev/null 2>&1 || true

  rm -rf "$APP_DIR" "$DATA_DIR"

  if [ -f "/swapfile_9router_build" ]; then
    swapoff "/swapfile_9router_build" 2>/dev/null || true
    rm -f "/swapfile_9router_build"
  fi

  echo
  echo "9router has been removed."
  echo "Node.js, npm, PM2, Git and other shared dependencies were left installed."
}

case "\${1:-install}" in
  install|update)
    install_deps
    mkdir -p "$APP_DIR"
    create_or_update_env
    install_app
    check_firewall
    verify_service || true
    show_result
    ;;
  uninstall|remove|delete)
    uninstall
    ;;
  *)
    echo "Usage:"
    echo "  $0                  Install / update 9Router"
    echo "  $0 install          Install / update 9Router"
    echo "  $0 uninstall       Remove 9Router and its data"
    exit 1
    ;;
esac
