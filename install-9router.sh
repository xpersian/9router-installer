#!/bin/bash
set -e

APP_DIR="/opt/9router"
DATA_DIR="/var/lib/9router"
APP_NAME="9router"
PORT="20128"
REPO="https://github.com/decolua/9router.git"

install_deps(){
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

create_env(){
 mkdir -p "$DATA_DIR"
 if [ ! -f "$APP_DIR/.env" ]; then
  echo "Creating environment file"
  read -p "Dashboard password: " INITIAL_PASSWORD
  cat > "$APP_DIR/.env" <<EOF
JWT_SECRET=$(openssl rand -hex 32)
INITIAL_PASSWORD=$INITIAL_PASSWORD
DATA_DIR=$DATA_DIR
PORT=$PORT
HOSTNAME=0.0.0.0
NODE_ENV=production
NEXT_PUBLIC_BASE_URL=http://$(curl -s ifconfig.me):$PORT
NEXT_PUBLIC_CLOUD_URL=https://9router.com
API_KEY_SECRET=$(openssl rand -hex 32)
MACHINE_ID_SALT=$(openssl rand -hex 32)
EOF
  chmod 600 "$APP_DIR/.env"
 fi
}

install_app(){
 if [ ! -d "$APP_DIR/.git" ]; then
  rm -rf "$APP_DIR"
  git clone "$REPO" "$APP_DIR"
 else
  cd "$APP_DIR"
  git pull
 fi

 cd "$APP_DIR"
 npm install
 npm run build

 pm2 delete "$APP_NAME" 2>/dev/null || true
 pm2 start npm --name "$APP_NAME" -- start
 pm2 save
 pm2 startup systemd -u root --hp /root || true
}

install_deps
mkdir -p "$APP_DIR"
create_env
install_app

echo ""
echo "9router installed/updated successfully"
echo "URL: http://$(curl -s ifconfig.me):$PORT"
