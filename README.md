# 9Router Docker Installer

[فارسی](README.fa.md) | English

Fast VPS installer for 9Router using the published Docker image.

## Features

- Uses the published multi-platform image: decolua/9router:latest
- No Node.js build and no npm build on the VPS
- Persistent data: /opt/9router/data
- Automatic start after reboot with Docker restart policy
- Service port: 20128
- Uses IPv4 for the direct public URL when no domain is selected
- First-run dashboard password prompt
- Enter without a password to generate and display a reasonably strong password
- Existing dashboard password is preserved on future runs
- Cloudflare Quick Tunnel status, enable, disable and URL refresh from the menu
- Tunnel-enabled state is persisted by 9Router and can auto-resume after restart
- Daily automatic image update using systemd timer
- Firewall detection only; no firewall rules are opened or modified
- Complete uninstall option

## Install

Run as root:

~~~bash
curl -fsSL https://github.com/xpersian/9router-installer/archive/refs/heads/main.tar.gz | tar -xzO --wildcards '*/9router.sh' | bash
~~~

A numbered menu is shown.

## Menu

~~~text
1) Install / Update 9Router
2) Update now
3) Status
4) Tunnel status
5) Enable Tunnel
6) Disable Tunnel
7) Refresh Tunnel URL
8) Show logs
9) Restart 9Router
10) Uninstall 9Router
0) Exit
~~~

## First setup

### URL

The installer asks whether you have a domain.

Without a domain it detects the public IPv4 and uses:

~~~text
http://SERVER_IPV4:20128
~~~

With a domain it uses:

~~~text
http://DOMAIN:20128
~~~

This installer does not configure HTTPS, Nginx, Apache or a reverse proxy.

### Dashboard password

On first setup:

~~~text
Dashboard password (Enter = auto-generate):
~~~

Enter your own password, or press Enter.

An automatically generated password looks similar to:

~~~text
9Router@03cb644633
~~~

The exact generated password is printed and stored in /opt/9router/.env.

On later runs an existing password is preserved and is not regenerated.

## Docker

The container is equivalent to:

~~~bash
docker run -d \
  --name 9router \
  --restart unless-stopped \
  -p 0.0.0.0:20128:20128 \
  --env-file /opt/9router/.env \
  -v /opt/9router/data:/app/data \
  decolua/9router:latest
~~~

The upstream image defines PORT=20128, HOSTNAME=0.0.0.0 and DATA_DIR=/app/data.

## Environment

The installer sets the main upstream deployment variables:

~~~text
JWT_SECRET
INITIAL_PASSWORD
DATA_DIR=/app/data
PORT=20128
HOSTNAME=0.0.0.0
NODE_ENV=production
BASE_URL
CLOUD_URL=https://9router.com
NEXT_PUBLIC_BASE_URL
NEXT_PUBLIC_CLOUD_URL=https://9router.com
API_KEY_SECRET
MACHINE_ID_SALT
ENABLE_REQUEST_LOGS=false
AUTH_COOKIE_SECURE=false
REQUIRE_API_KEY=false
~~~

## Tunnel

The menu supports:

~~~text
Tunnel status
Enable Tunnel
Disable Tunnel
Refresh Tunnel URL
~~~

The script uses the local 9Router CLI token to call the local Tunnel API. The token itself is not printed.

Enabling the Tunnel stores the state in 9Router. The upstream startup code can automatically resume an enabled Tunnel after the container restarts.

Refreshing the Tunnel disables it and enables it again, which may create a new public URL.

## Automatic updates

A systemd timer named 9router-update.timer is installed.

It checks decolua/9router:latest every day around 04:30 with a small randomized delay.

The container is recreated only when a new image is available or the container is missing/stopped. The data directory and .env are preserved.

Check the timer:

~~~bash
systemctl status 9router-update.timer
~~~

Manual update:

~~~bash
bash <(curl -fsSL https://github.com/xpersian/9router-installer/archive/refs/heads/main.tar.gz | tar -xzO --wildcards '*/9router.sh') update
~~~

## Existing installations

Existing configuration at /opt/9router/.env is preserved.

If old application data exists at /var/lib/9router and /opt/9router/data is empty, the installer copies the old data into the new Docker data directory.

An existing container named 9router is replaced with the published image while preserving the host data directory.

## Firewall

No firewall rule is opened or changed.

If UFW, firewalld or nftables is installed, the installer only prints a warning.

A separate firewall or security group in the VPS provider panel can still affect TCP 20128.

## Uninstall

~~~bash
bash <(curl -fsSL https://github.com/xpersian/9router-installer/archive/refs/heads/main.tar.gz | tar -xzO --wildcards '*/9router.sh') uninstall
~~~

Type REMOVE to confirm.

The following are removed:

~~~text
/opt/9router
9router-update.timer
9router-update.service
/usr/local/sbin/9router-update
~~~

Docker itself is not removed.

## Useful commands

~~~bash
docker ps
docker logs -f 9router
docker restart 9router
systemctl status 9router-update.timer
~~~

## Upstream

9Router:
https://github.com/decolua/9router

Docker image:
https://hub.docker.com/r/decolua/9router

This repository is an independent installer/helper.
