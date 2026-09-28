# 9Router npm Installer

[فارسی](README.fa.md) | English

One-command installer and updater for [9Router](https://github.com/decolua/9router) from source on Ubuntu/Debian.

## Features

- Installs Node.js 22, Git, build tools and PM2 when needed
- Clones/updates the upstream 9Router source repository
- Builds and runs 9Router directly with npm/PM2
- Uses port 20128 and binds to 0.0.0.0
- Creates secure random JWT/API secrets
- Interactive dashboard password setup with confirmation
- Works correctly when launched with `curl ... | bash` by reading prompts from `/dev/tty`
- Asks whether you want to use a domain; otherwise detects the server's public IPv4
- Repairs older installations that accidentally saved an IPv6 public URL
- Preserves the existing `.env` on updates
- Opens TCP 20128 in UFW only when UFW is already active
- Verifies that 9Router is listening and that the local dashboard responds
- Adds temporary build swap when the server has less than 2 GiB total swap

## Install or update

Run as root:

```bash
curl -fsSL https://raw.githubusercontent.com/xpersian/9router-installer/main/install-9router.sh | bash
```

The first run asks for a domain and dashboard password.

When no domain is selected, the script uses:

```text
http://SERVER_IPV4:20128
```

When a domain is selected, the direct URL is:

```text
http://DOMAIN:20128
```

This installer does not configure HTTPS, Nginx, Apache, or a reverse proxy.

Run the same command again to update 9Router. The existing `.env` and application data are preserved.

## Dashboard

Open:

```text
http://SERVER_IPV4:20128/dashboard
```

or the configured domain URL.

The dashboard password is the password chosen during the first setup. If an older installation has an empty `INITIAL_PASSWORD`, the installer will ask for a new one.

## Useful commands

```bash
pm2 status
pm2 logs 9router
pm2 restart 9router
```

## Files

```text
/opt/9router/.env
/opt/9router/        # application source
/var/lib/9router/    # persistent application data
```

The `.env` file is created with mode 600.

## Firewall

If UFW is active, the installer allows TCP port 20128.

A VPS provider can also have a separate network firewall/security group. That external firewall must allow TCP 20128 for direct browser access.

## Disclaimer

This repository is an independent installer/helper project. 9Router itself is maintained by the upstream project.
