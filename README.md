# 9Router Docker Installer

[فارسی](README.fa.md) | English

A one-command installer and management script for running [9Router](https://github.com/decolua/9router) with Docker on Debian/Ubuntu.

## Features

- Installs Docker when needed
- Uses `decolua/9router:latest`
- Runs 9Router on port `20128`
- Keeps persistent data in `/opt/9router/data`
- Generates random application secrets and an initial password
- Automatically starts 9Router after server reboot
- Checks for image updates daily around `04:30`
- Recreates the container only when a new image is available
- Preserves data and configuration during updates
- Automatically handles the local CLI token required by protected Tunnel API routes
- Shows Tunnel status and can enable or disable the Tunnel from the script
- Opens TCP port `20128` in UFW only when UFW is already active
- Does not modify Apache, Nginx, or port `443`
- Includes status, logs, restart, update, repair, and complete uninstall options

## Quick install

Run as `root`:

```bash
curl -fsSL https://raw.githubusercontent.com/xpersian/9router-installer/main/install-9router.sh | bash
```

The installer opens an interactive management menu. For direct installation/repair:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/xpersian/9router-installer/main/install-9router.sh) install
```

## Management menu

Run the one-line command again to open the menu:

```bash
curl -fsSL https://raw.githubusercontent.com/xpersian/9router-installer/main/install-9router.sh | bash
```

Available options:

```text
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
```

### Install / Repair

Installs missing dependencies, creates the required configuration if it does not already exist, pulls the latest image, and recreates the `9router` container while preserving `/opt/9router/data`.

### Update now

Immediately pulls the latest `decolua/9router:latest` image. The container is recreated only if the image has changed.

### Status

Shows the Docker container status and attempts to query the local 9Router health endpoint.

### Tunnel

The script includes dedicated options for:

- Checking Tunnel status
- Enabling the Tunnel
- Disabling the Tunnel

Protected 9Router Tunnel routes can require a local CLI token. The script calculates the required token from the local 9Router installation and sends it directly to the local API. The token is not intended to be manually copied into the dashboard.

After installation, the script also asks whether you want to enable the Tunnel immediately.

If Tunnel activation fails, use **Show logs** and **Tunnel status** from the menu to inspect the result.

## Access

After installation:

```text
http://SERVER_IP:20128
```

OpenAI-compatible API base URL:

```text
http://SERVER_IP:20128/v1
```

The generated initial password is displayed at the end of installation. Store it securely and change it from the 9Router dashboard if supported by your installed version.

## Automatic updates

A systemd timer checks for a new Docker image every day at approximately `04:30`, with a random delay of up to 10 minutes.

Check the timer:

```bash
systemctl status 9router-update.timer
```

Check updater logs:

```bash
journalctl -u 9router-update.service
```

Or:

```bash
cat /opt/9router/update.log
```

Run the updater directly:

```bash
/opt/9router/update.sh
```

You can also choose **Update now** from the management menu.

## Files

```text
/opt/9router/
├── .env
├── data/
├── update.sh
└── update.log
```

The `.env` file is created with restrictive permissions (`600`). Persistent application data is stored outside the container.

## Logs and restart

From the management menu you can show logs or restart 9Router. Manual commands are also available:

```bash
docker logs -f 9router
docker restart 9router
```

## Complete uninstall

Choose:

```text
9) Uninstall completely
```

The script asks for confirmation before removing:

- The `9router` Docker container
- The 9Router Docker image
- The automatic update timer and service
- `/opt/9router`, including persistent data and configuration

Docker itself is **not removed**.

> Warning: complete uninstall permanently deletes the local 9Router data directory.

## Port 443 and existing web services

The installer intentionally does not use or modify TCP port `443`. Existing Apache, Nginx, or other services are left untouched.

## Security

By default, Docker publishes port `20128` as configured by the installer. If the server is publicly reachable, restrict access with your firewall or security group when appropriate and keep 9Router authentication enabled.

The Tunnel automation uses the locally generated CLI token only for requests made from the server to the local 9Router API. Do not publish the CLI secret or token.

## Disclaimer

This repository is an independent installer/helper project. [9Router](https://github.com/decolua/9router) and its Docker image are maintained by the upstream project and its authors.
