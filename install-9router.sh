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

  while true; do
    read_secret_tty "Choose dashboard password: " p1

    [ -n "$p1" ] || { echo "Password cannot be empty."; continue; }
    [ "\${#p1}" -ge 6 ] || { echo "Password must be at least 6 characters."; continue; }

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

  # Fix the old piped-script bug: read received EOF and created an empty password.
  if [ -z "$existing_password" ]; then
    echo
    echo "The existing configuration has an empty INITIAL_PASSWORD."
    prompt_password

    if grep -q '^INITIAL_PASSWORD=' "$APP_DIR/.env"; then
      sed -i '/^INITIAL_PASSWORD=/d' "$APP_DIR/.env"
    fi

    printf 'INITIAL_PASSWORD=%s\n' "$INITIAL_PASSWORD" >> "$APP_DIR/.env"
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

    # Old versions of this installer could accidentally save an IPv6 URL.
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
    echo "Configuration saved."
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

install_app() {
  if [ ! -d "$APP_DIR/.git" ]; then
    rm -rf "$APP_DIR"
    git clone "$REPO" "$APP_DIR"
  else
    cd "$APP_DIR"
    git pull --ff-only
  fi

  cd "$APP_DIR"
  npm install

  prepare_build_swap
  trap cleanup_build_swap EXIT

  echo "Building 9router..."
  MAKEFLAGS="-j1" NODE_OPTIONS="--max-old-space-size=768" npm run build

  cleanup_build_swap
  trap - EXIT

  pm2 delete "$APP_NAME" 2>/dev/null || true
  pm2 start npm --name "$APP_NAME" -- start
  pm2 save
  pm2 startup systemd -u root --hp /root >/dev/null 2>&1 || true
}

open_firewall() {
  if command -v ufw >/dev/null 2>&1 && ufw status | grep -q '^Status: active'; then
    ufw allow "$PORT/tcp" comment '9Router' >/dev/null || true
    echo "UFW: TCP $PORT allowed."
  else
    echo "UFW is not active; no local firewall rule was changed."
    echo "If your VPS provider has a separate firewall/security group, allow TCP $PORT there too."
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
  echo
  echo "The dashboard password is the one you chose during setup."
  echo "Status: pm2 status"
  echo "Logs:   pm2 logs $APP_NAME"
  echo "========================================"
}

install_deps
mkdir -p "$APP_DIR"
create_or_update_env
install_app
open_firewall
verify_service || true
show_result
