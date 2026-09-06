#!/usr/bin/env bash
set -Eeuo pipefail
APP_DIR=/opt/9router; DATA_DIR="$APP_DIR/data"; ENV_FILE="$APP_DIR/.env"; CONTAINER_NAME=9router; IMAGE=decolua/9router:latest; PORT=20128
UPDATE_SCRIPT="$APP_DIR/update.sh"; UPDATE_SERVICE=/etc/systemd/system/9router-update.service; UPDATE_TIMER=/etc/systemd/system/9router-update.timer
log(){ echo "[+] $*"; }; warn(){ echo "[!] $*"; }; fail(){ echo "[ERROR] $*" >&2; exit 1; }
need_root(){ [[ $EUID -eq 0 ]] || fail "Run as root."; }
# Use a dedicated terminal FD. This works with process substitution and normal script execution.
if [[ -e /dev/tty ]]; then exec 3</dev/tty 4>/dev/tty 2>/dev/null || true; fi
ask(){ local p="$1"; [[ -e /dev/fd/3 ]] || return 1; printf '%s' "$p" >&4; IFS= read -r REPLY <&3; }
install_deps(){ apt-get update -qq; apt-get install -y -qq ca-certificates curl openssl >/dev/null; }
ensure_docker(){ command -v docker >/dev/null 2>&1 || { curl -fsSL https://get.docker.com | sh; }; systemctl enable --now docker; }
write_env(){ mkdir -p "$DATA_DIR"; chmod 700 "$APP_DIR" "$DATA_DIR"; [[ -f "$ENV_FILE" ]] && return; cat > "$ENV_FILE" <<EOF
NODE_ENV=production
PORT=$PORT
HOSTNAME=0.0.0.0
DATA_DIR=/app/data
JWT_SECRET=$(openssl rand -hex 32)
INITIAL_PASSWORD=$(openssl rand -base64 32 | tr -dc 'A-Za-z0-9' | head -c 24)
API_KEY_SECRET=$(openssl rand -hex 32)
MACHINE_ID_SALT=$(openssl rand -hex 32)
NEXT_PUBLIC_BASE_URL=http://127.0.0.1:$PORT
NEXT_PUBLIC_CLOUD_URL=https://9router.com
ENABLE_REQUEST_LOGS=false
EOF
chmod 600 "$ENV_FILE"; }
run_container(){ docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true; docker run -d --name "$CONTAINER_NAME" --restart unless-stopped -p "$PORT:$PORT" --env-file "$ENV_FILE" -v "$DATA_DIR:/app/data" "$IMAGE" >/dev/null; sleep 5; docker ps --format '{{.Names}}' | grep -qx "$CONTAINER_NAME" || fail "9Router failed to start."; }
write_update(){ cat > "$UPDATE_SCRIPT" <<'EOF'
#!/usr/bin/env bash
set -e
D=/opt/9router; C=9router; I=decolua/9router:latest
docker pull "$I"
L=$(docker image inspect "$I" -f '{{.Id}}'); O=$(docker inspect "$C" -f '{{.Image}}' 2>/dev/null || true)
[ "$L" = "$O" ] && exit 0
docker rm -f "$C" 2>/dev/null || true
docker run -d --name "$C" --restart unless-stopped -p 20128:20128 --env-file "$D/.env" -v "$D/data:/app/data" "$I"
EOF
chmod 700 "$UPDATE_SCRIPT"; cat > "$UPDATE_SERVICE" <<EOF
[Unit]
After=docker.service
Requires=docker.service
[Service]
Type=oneshot
ExecStart=$UPDATE_SCRIPT
EOF
cat > "$UPDATE_TIMER" <<EOF
[Unit]
[Timer]
OnCalendar=*-*-* 04:30:00
Persistent=true
RandomizedDelaySec=10m
[Install]
WantedBy=timers.target
EOF
systemctl daemon-reload; systemctl enable --now 9router-update.timer; }
cli_token(){ docker exec "$CONTAINER_NAME" node -e 'const f=require("fs"),c=require("crypto");let r=p=>{try{return f.readFileSync(p,"utf8").trim()}catch(e){return ""}},i=r("/app/data/machine-id")||r("/etc/machine-id"),s=r("/app/data/auth/cli-secret");if(!i||!s)process.exit(2);console.log(c.createHash("sha256").update(i+"9r-cli-auth"+s).digest("hex").slice(0,16))' 2>/dev/null; }
tunnel(){ local a=$1 t; t=$(cli_token || true); [[ -n $t ]] || fail "CLI token unavailable."; curl -sS -X POST -H "x-9r-cli-token: $t" "http://127.0.0.1:$PORT/api/tunnel/$a"; echo; }
install_9router(){ install_deps; ensure_docker; write_env; docker pull "$IMAGE"; run_container; write_update; echo "9Router installed."; if ask "Enable Tunnel now? [y/N]: "; then [[ $REPLY =~ ^[Yy]$ ]] && tunnel enable || true; fi; }
status(){ docker ps --filter "name=^/$CONTAINER_NAME$"; }
tunnel_status(){ local t; t=$(cli_token || true); [[ -n $t ]] || fail "CLI token unavailable."; curl -sS -H "x-9r-cli-token: $t" "http://127.0.0.1:$PORT/api/tunnel/status"; echo; }
uninstall(){ ask "Delete 9Router and ALL data? [y/N]: " || return; [[ $REPLY =~ ^[Yy]$ ]] || return; systemctl disable --now 9router-update.timer 2>/dev/null || true; rm -f "$UPDATE_SERVICE" "$UPDATE_TIMER"; docker rm -f "$CONTAINER_NAME" 2>/dev/null || true; rm -rf "$APP_DIR"; systemctl daemon-reload; echo "Removed."; }
menu(){ while :; do cat >&4 <<'EOF'

========== 9router-installer ==========
1) Install / Repair 9Router
2) Update now
3) Status
4) Tunnel status
5) Enable Tunnel
6) Disable Tunnel
7) Show logs
8) Restart 9Router
9) Uninstall completely
0) Exit
EOF
ask "Select: " || fail "No interactive terminal. Run: bash <(curl -fsSL https://raw.githubusercontent.com/xpersian/9router-installer/main/install-9router.sh)"
case "$REPLY" in 1) install_9router;;2) "$UPDATE_SCRIPT";;3) status;;4) tunnel_status;;5) tunnel enable;;6) tunnel disable;;7) docker logs --tail 150 "$CONTAINER_NAME";;8) docker restart "$CONTAINER_NAME";;9) uninstall;;0) exit;;*) warn "Invalid option.";;esac; done; }
need_root
case "${1:-menu}" in install) install_9router;;menu) menu;;*) fail "Usage: $0 [install|menu]";;esac
