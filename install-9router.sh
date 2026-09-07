#!/usr/bin/env bash
set -Eeuo pipefail
APP_DIR=/opt/9router; DATA_DIR="$APP_DIR/data"; ENV_FILE="$APP_DIR/.env"; CONTAINER_NAME=9router; IMAGE=decolua/9router:latest; PORT=20128
UPDATE_SCRIPT="$APP_DIR/update.sh"; UPDATE_SERVICE=/etc/systemd/system/9router-update.service; UPDATE_TIMER=/etc/systemd/system/9router-update.timer
log(){ echo "[+] $*"; }; warn(){ echo "[!] $*"; }; fail(){ echo "[ERROR] $*" >&2; return 1; }
need_root(){ [[ $EUID -eq 0 ]] || fail "Run as root."; }
if [[ -e /dev/tty ]]; then exec 3</dev/tty 4>/dev/tty 2>/dev/null || true; fi
ask(){ local p="$1"; [[ -e /dev/fd/3 ]] || return 1; printf '%s' "$p" >&4; IFS= read -r REPLY <&3; }
install_deps(){ apt-get update -qq; apt-get install -y -qq ca-certificates curl openssl >/dev/null; }
ensure_docker(){ command -v docker >/dev/null 2>&1 || { curl -fsSL https://get.docker.com | sh; }; systemctl enable --now docker; }
generate_password(){ openssl rand -hex 16; }
write_env(){
  mkdir -p "$DATA_DIR/auth"; chmod 700 "$APP_DIR" "$DATA_DIR" "$DATA_DIR/auth";
  [[ -s "$DATA_DIR/machine-id" ]] || openssl rand -hex 32 > "$DATA_DIR/machine-id";
  [[ -s "$DATA_DIR/auth/cli-secret" ]] || openssl rand -hex 32 > "$DATA_DIR/auth/cli-secret";
  chmod 600 "$DATA_DIR/machine-id" "$DATA_DIR/auth/cli-secret";
  if [[ -f "$ENV_FILE" ]]; then
    grep -q '^INITIAL_PASSWORD=' "$ENV_FILE" || { local p; p=$(generate_password); printf '\nINITIAL_PASSWORD=%s\n' "$p" >> "$ENV_FILE"; chmod 600 "$ENV_FILE"; }
    return 0
  fi
  local password
  echo >&4
  ask "Dashboard password (leave empty = secure random 24 chars): " || true
  password="${REPLY:-}"
  if [[ -z "$password" ]]; then password=$(generate_password); fi
  if (( ${#password} < 8 )); then fail "Password must be at least 8 characters."; fi
  cat > "$ENV_FILE" <<EOF
NODE_ENV=production
PORT=$PORT
HOSTNAME=0.0.0.0
DATA_DIR=/app/data
JWT_SECRET=$(openssl rand -hex 32)
INITIAL_PASSWORD=$password
API_KEY_SECRET=$(openssl rand -hex 32)
MACHINE_ID_SALT=$(openssl rand -hex 32)
NEXT_PUBLIC_BASE_URL=http://127.0.0.1:$PORT
NEXT_PUBLIC_CLOUD_URL=https://9router.com
ENABLE_REQUEST_LOGS=false
EOF
  chmod 600 "$ENV_FILE"
}
get_password(){ [[ -f "$ENV_FILE" ]] && sed -n 's/^INITIAL_PASSWORD=//p' "$ENV_FILE" | head -n1 || true; }
container_exists(){ docker inspect "$CONTAINER_NAME" >/dev/null 2>&1; }
container_running(){ [[ "$(docker inspect -f '{{.State.Running}}' "$CONTAINER_NAME" 2>/dev/null || true)" == "true" ]]; }
require_installed(){ container_exists || { warn "9Router is not installed. Install it first with option 1."; return 1; }; container_running || { warn "9Router is installed but not running. Use option 8 to restart it."; return 1; }; }
run_container(){ docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true; docker run -d --name "$CONTAINER_NAME" --restart unless-stopped -p "$PORT:$PORT" --env-file "$ENV_FILE" -v "$DATA_DIR:/app/data" "$IMAGE" >/dev/null; for _ in {1..20}; do container_running && break; sleep 1; done; container_running || fail "9Router failed to start."; }
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
cli_token(){ docker exec "$CONTAINER_NAME" node -e 'const fs=require("fs"),crypto=require("crypto");const r=p=>{try{return fs.readFileSync(p,"utf8").trim()}catch(e){return ""}};const i=r("/app/data/machine-id"),s=r("/app/data/auth/cli-secret");if(!i||!s)process.exit(2);process.stdout.write(crypto.createHash("sha256").update(i+"9r-cli-auth"+s).digest("hex").slice(0,16));' 2>/dev/null; }
api_json(){ local path="$1" t; t=$(cli_token || true); [[ -n "$t" ]] || { warn "CLI token unavailable."; return 1; }; curl -fsS --max-time 15 -H "x-9r-cli-token: $t" "http://127.0.0.1:$PORT$path"; }
tunnel(){ local a=$1 t out; require_installed || return 1; t=$(cli_token || true); [[ -n "$t" ]] || { warn "CLI token unavailable."; return 1; }; out=$(curl -sS --max-time 60 -X POST -H "x-9r-cli-token: $t" "http://127.0.0.1:$PORT/api/tunnel/$a" || true); [[ -n "$out" ]] || { warn "Tunnel API request failed."; return 1; }; return 0; }
print_tunnel_status(){
  if ! require_installed >/dev/null 2>&1; then echo "Tunnel      : NOT INSTALLED"; return 0; fi
  local out; out=$(api_json "/api/tunnel/status" 2>/dev/null || true)
  [[ -n "$out" ]] || { echo "Tunnel      : UNKNOWN"; return 0; }
  printf '%s' "$out" | docker exec -i "$CONTAINER_NAME" node -e '
let s="";
process.stdin.on("data",d=>s+=d).on("end",()=>{
 try{
  const x=JSON.parse(s),t=x.tunnel||x.data?.tunnel||x.data||x,ts=x.tailscale||x.data?.tailscale||{};
  console.log("Tunnel      : "+(t.enabled===true?"ENABLED":t.enabled===false?"DISABLED":"UNKNOWN"));
  if(t.running!==undefined) console.log("Running     : "+(t.running?"YES":"NO"));
  if(t.publicUrl) console.log("Public URL  : "+t.publicUrl);
  if(t.tunnelUrl) console.log("Tunnel URL  : "+t.tunnelUrl);
  if(t.shortId) console.log("Short ID    : "+t.shortId);
  if(t.error) console.log("Error       : "+t.error);
  if(ts.enabled!==undefined) console.log("Tailscale   : "+(ts.enabled?"ENABLED":"DISABLED"));
 }catch(e){console.log("Tunnel      : UNKNOWN")}
});
' 2>/dev/null || echo "Tunnel      : UNKNOWN"
}
show_info(){
  echo; echo "========== 9Router ==========";
  if ! container_exists; then
    echo "Status      : NOT INSTALLED"; echo "Dashboard   : -"; echo "Password    : -"; echo "CLI Token   : -"; echo "Tunnel      : NOT INSTALLED"; echo "=============================="; return 0;
  fi
  docker ps --filter "name=^/$CONTAINER_NAME$" --format 'Container   : {{.Names}}\nStatus      : {{.Status}}\nImage       : {{.Image}}\nPorts       : {{.Ports}}';
  local t p; t=$(cli_token || true); p=$(get_password); [[ -n "$t" ]] && echo "CLI Token   : $t" || echo "CLI Token   : UNAVAILABLE"; [[ -n "$p" ]] && echo "Password    : $p" || echo "Password    : UNKNOWN";
  echo "Dashboard   : http://$(hostname -I | awk '{print $1}'):$PORT"; print_tunnel_status; echo "==============================";
}
install_9router(){ install_deps; ensure_docker; write_env; docker pull "$IMAGE"; run_container; write_update; echo "9Router installed."; echo "Dashboard password: $(get_password)"; if ask "Enable Tunnel now? [y/N]: "; then [[ $REPLY =~ ^[Yy]$ ]] && { tunnel enable; sleep 2; }; fi; show_info; }
status(){ show_info; }
tunnel_status(){ echo; echo "========== Tunnel status =========="; print_tunnel_status; if container_running; then local t; t=$(cli_token || true); [[ -n "$t" ]] && echo "CLI Token   : $t" || echo "CLI Token   : UNAVAILABLE"; fi; echo "==================================="; }
change_tunnel(){
  require_installed || return 0
  echo; echo "========== Change Tunnel =========="; echo "Current:"; print_tunnel_status; echo
  echo "1) Restart Tunnel (refresh URL)"; echo "2) Disable then Enable (refresh URL)"; echo "0) Back"
  ask "Select: " || return 0
  case "$REPLY" in
    1)
      echo "Restarting Tunnel..."
      if tunnel restart; then sleep 3; echo "Tunnel refreshed successfully."; else warn "Tunnel restart failed."; return 0; fi
      echo; echo "Updated:"; print_tunnel_status;;
    2)
      echo "Disabling Tunnel..."
      if tunnel disable; then sleep 3; else warn "Tunnel disable failed."; return 0; fi
      echo "Enabling Tunnel..."
      if tunnel enable; then sleep 3; echo "Tunnel refreshed successfully."; else warn "Tunnel enable failed."; return 0; fi
      echo; echo "Updated:"; print_tunnel_status;;
    0) return 0;;
    *) warn "Invalid option.";;
  esac
}
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
10) Change / Refresh Tunnel URL
0) Exit
EOF
ask "Select: " || fail "No interactive terminal. Run: bash <(curl -fsSL https://raw.githubusercontent.com/xpersian/9router-installer/main/install-9router.sh)"
case "$REPLY" in
1) install_9router;;
2) if [[ -x "$UPDATE_SCRIPT" ]]; then "$UPDATE_SCRIPT"; show_info; else warn "9Router is not installed."; fi;;
3) status;;
4) tunnel_status;;
5) if tunnel enable; then sleep 2; tunnel_status; fi;;
6) if tunnel disable; then sleep 1; tunnel_status; fi;;
7) if require_installed; then docker logs --tail 150 "$CONTAINER_NAME"; fi;;
8) if require_installed; then docker restart "$CONTAINER_NAME"; sleep 3; show_info; fi;;
9) uninstall;;
10) change_tunnel;;
0) exit;;
*) warn "Invalid option.";;
esac; done; }
need_root
case "${1:-menu}" in install) install_9router;;menu) menu;;*) fail "Usage: $0 [install|menu]";;esac
