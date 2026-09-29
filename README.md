# 9Router Installer

Simple Docker installer for [9Router](https://github.com/decolua/9router).

## Install

Run as root:

```bash
curl -fsSL https://github.com/xpersian/9router-installer/raw/refs/heads/main/9router.sh | bash
```

The script installs Docker if needed, runs `decolua/9router:latest), exposes port `20128` on `0.0.0.0`, detects the server's public IPv4, and starts automatically after reboot.

First run asks for the dashboard password. Press Enter to generate one. The generated password is shown. Existing passwords are preserved on later runs.

## Menu

```text
1) Install / Update 9Router
2) Status
3) Restart 9Router
4) Uninstall 9Router
0) Exit
```

## Automatic update

A systemd timer checks the latest Docker image every day at 04:30 with a random delay of up to 10 minutes. The container is recreated only when a new image is available.

Manual update:

```bash
curl -fsSL https://github.com/xpersian/9router-installer/raw/refs/heads/main/9router.sh | bash -s -- update
```

## Access

```text
http://SERVER_IPV4:20128/dashboard
http://SERVER_IPV4:20128/v1
```

The installer does not open or modify firewall rules. If a firewall is installed, it only shows a warning.

## Uninstall

Choose option 4 or run:

```bash
curl -fsSL https://github.com/xpersian/9router-installer/raw/refs/heads/main/9router.sh | bash -s -- uninstall
```

This removes 9Router, its Docker image, configuration and data. Docker remains installed.
