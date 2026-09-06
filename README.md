# 9Router Docker Installer

One-command Docker installer for [9Router](https://github.com/decolua/9router).

## Features

- Installs Docker on Debian/Ubuntu when needed
- Uses the official published image: `decolua/9router:latest`
- Runs 9Router on the default port `20128`
- Persists application data under `/opt/9router/data`
- Generates random secrets and an initial password
- Enables Docker restart policy for reboot persistence
- Creates a daily systemd update timer
- Pulls the latest image and recreates the container only when the image changes
- Preserves persistent data during updates
- Opens TCP 20128 in UFW only when UFW is already active
- Does not modify Apache or port 443

## One-line installation

```bash
curl -fsSL https://raw.githubusercontent.com/xpersian/9router-installer/main/install-9router.sh | bash
```

Run it as `root`.

## Access

After installation:

```text
http://SERVER_IP:20128
```

The API is available at:

```text
http://SERVER_IP:20128/v1
```

The installer prints the generated initial password at the end. Save it and change it from the 9Router dashboard if supported by the installed version.

## Files

```text
/opt/9router/
├── .env
├── data/
├── update.sh
└── update.log
```

The environment file is created with restrictive permissions (`600`). Persistent application data is kept outside the container.

## Automatic updates

A systemd timer checks the Docker image every day around 04:30, with a random delay of up to 10 minutes.

Check the timer:

```bash
systemctl status 9router-update.timer
```

Check update logs:

```bash
journalctl -u 9router-update.service
```

Or:

```bash
cat /opt/9router/update.log
```

Run an update check manually:

```bash
/opt/9router/update.sh
```

## Container management

```bash
docker ps
docker logs -f 9router
docker restart 9router
docker stop 9router
docker start 9router
```

## Cloud / proxy

The installer does not assume that setting the 9Router Cloud URL automatically creates a public Cloud Endpoint. Cloud Sync/Endpoint functionality depends on the installed 9Router version and its dashboard configuration.

The local instance remains directly reachable at port `20128`.

## Port 443

This installer intentionally does **not** use or modify TCP port 443. This is useful on servers where Apache, Mirza, or other HTTPS services already occupy port 443.

## Security

Port `20128` is exposed directly by Docker. If this server is publicly reachable, restrict access with your firewall/security-group policy when appropriate and use the authentication/security options provided by your 9Router version.

## Uninstall

To remove the container and updater while keeping the data:

```bash
docker rm -f 9router
systemctl disable --now 9router-update.timer
rm -f /etc/systemd/system/9router-update.timer
rm -f /etc/systemd/system/9router-update.service
systemctl daemon-reload
rm -rf /opt/9router
```

Only run the final `rm -rf /opt/9router` if you intentionally want to delete the persistent 9Router data and configuration.

## Disclaimer

This repository is an independent installer/helper script. 9Router and its Docker image are maintained by their respective upstream project authors.
