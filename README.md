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
- On the first setup, pressing Enter generates and displays a simple, reasonably strong password
- On later runs, an existing dashboard password is preserved and never changed
- Works correctly when launched with `curl ... | bash` by reading prompts from `/dev/tty`
- Asks whether you want to use a domain; otherwise detects the server's public IPv4
- Repairs older installations that accidentally saved an IPv6 public URL
- Preserves the existing `.env` on updates
- Detects common firewall tools and warns when a firewall is installed; it does not open or modify any firewall port
- Verifies that 9Router is listening and that the local dashboard responds
- Adds temporary build swap when the server has less than 2 GiB total swap

## Install or update

Run as root:

```bash
curl -fsSL https://raw.githubusercontent.com/xpersian/9router-installer/main/install-9router.sh | bash
```

The first run asks for a domain and dashboard password. The same command is also the update command.

On the first setup, enter your own dashboard password or press Enter to generate one automatically. The generated password is displayed clearly and is preserved on every later update. When a password already exists, the script does not ask for a new one and does not change it.

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

The dashboard password is the password chosen during the first setup. If an older installation has an empty `INITIAL_PASSWORD`, the installer asks for a new one (or generates one when you press Enter). Otherwise, the existing password is preserved unchanged.

## Uninstall

To completely remove 9Router and its persistent data:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/xpersian/9router-installer/main/install-9router.sh) uninstall
```

The script asks for confirmation and requires typing `REMOVE`.

It removes:

```text
/opt/9router
/var/lib/9router
```

It does not remove Node.js, npm, PM2, Git, or change firewall rules.

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

The installer does not open or modify firewall rules.

If a common firewall tool is installed (UFW, firewalld, or nftables), the installer only reports a warning. If browser access is blocked, check the firewall rules yourself.

## Disclaimer

This repository is an independent installer/helper project. 9Router itself is maintained by the upstream project.
