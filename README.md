# 9Router npm Installer

[فارسی](README.fa.md) | English

One-command installer and updater for [9Router](https://github.com/decolua/9router) on Ubuntu/Debian.

## Features

- Installs Node.js 22, Git, build tools and PM2 when needed
- Runs 9Router directly from the upstream source with npm and PM2
- Uses port **20128** and binds to **0.0.0.0**
- First run asks whether to use a domain; otherwise it detects the server's public IPv4
- IPv6 is not used for the public URL
- First run asks for the dashboard password
- Pressing Enter generates a simple, reasonably strong password such as `9Router@a1b2c3d4e5` and displays it
- Later runs preserve the existing dashboard password and do not ask for a new one
- Repairs an older installation with an empty password or old IPv6 URL
- Uses `/dev/tty` for prompts, so it works with `curl ... | bash`
- If the server has less than 2 GiB total swap, a temporary 2 GiB swap file is used during installation/build
- Detects common firewall tools and warns, but never opens or changes firewall rules
- Includes Status, Logs, Restart and Uninstall options
- An existing `/opt/9router` directory is handled without failing on `destination path ... already exists`

## Install

Run as root:

~~~bash
curl -fsSL https://github.com/xpersian/9router-installer/archive/refs/heads/main.tar.gz | tar -xzO --wildcards '*/9router.sh' | bash
~~~

The script opens a numbered menu.

## Menu

~~~text
1) Install / Update 9Router
2) Status
3) Show logs
4) Restart 9Router
5) Uninstall 9Router
0) Exit
~~~

## First setup

### URL

The installer asks:

~~~text
Do you have a domain? (y/n):
~~~

With `n`, the public IPv4 is detected automatically and the URL becomes:

~~~text
http://SERVER_IPV4:20128
~~~

With `y`, enter the domain and the URL becomes:

~~~text
http://DOMAIN:20128
~~~

This installer does not configure HTTPS, Nginx, Apache or a reverse proxy.

### Dashboard password

On the first installation:

~~~text
Choose dashboard password (Enter = generate):
~~~

Enter your own password, or press Enter for an automatic password. The exact generated password is printed.

On every later update, the existing password is preserved and is not regenerated or replaced.

## Update

Run the same install command again and choose:

~~~text
1) Install / Update 9Router
~~~

The script updates the upstream source, installs dependencies, builds the application and restarts the PM2 process. The existing `.env` is preserved.

## Uninstall

To remove 9Router:

~~~bash
bash <(curl -fsSL https://github.com/xpersian/9router-installer/archive/refs/heads/main.tar.gz | tar -xzO --wildcards '*/9router.sh') uninstall
~~~

Or run the normal menu and choose option **5**.

The uninstall command requires typing `REMOVE` and removes:

~~~text
/opt/9router
/var/lib/9router
~~~

Node.js, npm, PM2 and Git are left installed. Firewall rules are not changed.

## Useful commands

~~~bash
pm2 status
pm2 logs 9router
pm2 restart 9router
~~~

## Files

~~~text
/opt/9router/.env
/opt/9router/          # 9Router source
/var/lib/9router/      # persistent application data
~~~

The `.env` file is created with permission mode `600`.

## Firewall

The installer never opens or modifies firewall rules.

If UFW, firewalld or nftables is installed, the script only prints a warning. A separate firewall/security group at the VPS provider can also block TCP **20128**.

## Disclaimer

This repository is an independent installer/helper project. 9Router itself is maintained by the upstream project.
