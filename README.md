# 9Router Installer

One-command installer for [9Router](https://github.com/decolua/9router) on Ubuntu/Debian.

## Install

Run as root:

\`\`\`bash
curl -fsSL https://github.com/xpersian/9router-installer/raw/refs/heads/main/9router.sh | bash
\`\`\`

A numbered menu is shown:

\`\`\`text
1) Install / Update 9Router
2) Status
3) Show logs
4) Restart 9Router
5) Uninstall 9Router
0) Exit
\`\`\`

The first installation asks for a domain and dashboard password. Press Enter at the password prompt to generate a password automatically and display it. On later runs, the existing dashboard password is preserved.

For uninstall, use option 5 or:

\`\`\`bash
curl -fsSL https://github.com/xpersian/9router-installer/raw/refs/heads/main/9router.sh | bash -s -- uninstall
\`\`\`

The installer does not open or modify firewall rules. If a firewall is installed, it only reports a warning.

### Docker

Published images (multi-platform `linux/amd64` + `linux/arm64`):

- Docker Hub: [`decolua/9router`](https://hub.docker.com/r/decolua/9router)
- GHCR: [`ghcr.io/decolua/9router`](https://github.com/decolua/9router/pkgs/container/9router)

**Quick start (use published image):**

```
docker run -d \
  --name 9router \
  -p 20128:20128 \
  -v "$HOME/.9router:/app/data" \
  -e DATA_DIR=/app/data \
  decolua/9router:latest
```

→ Open [http://localhost:20128](http://localhost:20128)

**Build from source (dev):**

```
git clone https://github.com/decolua/9router.git
cd 9router/app
docker build -t 9router .
docker run -d --name 9router -p 20128:20128 \
  -v "$HOME/.9router:/app/data" -e DATA_DIR=/app/data 9router
```

**Container defaults:**

- `PORT=20128`
- `HOSTNAME=0.0.0.0`

**Useful commands:**

```
docker logs -f 9router
docker restart 9router
docker stop 9router && docker rm 9router
docker pull decolua/9router:latest   # update to latest
```

**Data persistence:** `$HOME/.9router/db/data.sqlite` on host ↔ `/app/data/db/data.sqlite` in container.

### Environment Variables

| Variable                                             | Default                                  | Description                                                                         |
| ---------------------------------------------------- | ---------------------------------------- | ----------------------------------------------------------------------------------- |
| `JWT_SECRET`                                         | Auto-generated (`~/.9router/jwt-secret`) | JWT signing secret for dashboard auth cookie (override to share across instances)   |
| `INITIAL_PASSWORD`                                   | `123456`                                 | First login password when no saved hash exists                                      |
| `DATA_DIR`                                           | `~/.9router`                             | Main app data location (SQLite at `$DATA_DIR/db/data.sqlite`)                       |
| `PORT`                                               | framework default                        | Service port (`20128` in examples)                                                  |
| `HOSTNAME`                                           | framework default                        | Bind host (Docker defaults to `0.0.0.0`)                                            |
| `NODE_ENV`                                           | runtime default                          | Set `production` for deploy                                                         |
| `BASE_URL`                                           | `http://localhost:20128`                 | Server-side internal base URL used by cloud sync jobs                               |
| `CLOUD_URL`                                          | `https://9router.com`                    | Server-side cloud sync endpoint base URL                                            |
| `NEXT_PUBLIC_BASE_URL`                               | `http://localhost:3000`                  | Backward-compatible/public base URL (prefer `BASE_URL` for server runtime)          |
| `NEXT_PUBLIC_CLOUD_URL`                              | `https://9router.com`                    | Backward-compatible/public cloud URL (prefer `CLOUD_URL` for server runtime)        |
| `API_KEY_SECRET`                                     | `endpoint-proxy-api-key-secret`          | HMAC secret for generated API keys                                                  |
| `MACHINE_ID_SALT`                                    | `endpoint-proxy-salt`                    | Salt for stable machine ID hashing                                                  |
| `ENABLE_REQUEST_LOGS`                                | `false`                                  | Enables request/response logs under `logs/`                                         |
| `AUTH_COOKIE_SECURE`                                 | `false`                                  | Force `Secure` auth cookie (set `true` behind HTTPS reverse proxy)                  |
| `REQUIRE_API_KEY`                                    | `false`                                  | Enforce Bearer API key on `/v1/*` routes (recommended for internet-exposed deploys) |
| `HTTP_PROXY`, `HTTPS_PROXY`, `ALL_PROXY`, `NO_PROXY` | empty                                    | Optional outbound proxy for upstream provider calls                                 |
| `SEARXNG_URL`                                        | `http://localhost:8888/search`           | Endpoint for the built-in unauthenticated SearXNG web-search provider               |

Notes:

- Lowercase proxy variables are also supported: `http_proxy`, `https_proxy`, `all_proxy`, `no_proxy`.
- `.env` is not baked into Docker image (`.dockerignore`); inject runtime config with `--env-file` or `-e`.
- On Windows, `APPDATA` can be used for local storage path resolution.
- `INSTANCE_NAME` appears in older docs/env templates, but is currently not used at runtime.

### Runtime Files and Storage

- Main app state: `${DATA_DIR}/db/data.sqlite` (SQLite — providers, combos, aliases, keys, settings, usage history)
- Auto backups: `${DATA_DIR}/db/backups/`
- Optional request/translator logs: `<repo>/logs/...` when `ENABLE_REQUEST_LOGS=true`
- Both `${DATA_DIR}` and `~/.9router` resolve to the same location in a Docker container — the symlink `/root/.9router -> /app/data` is created at build time.

---

## 📊 Available Models

**View all available models**

-
-
-
-
-

*
*
*
*
*

-
-
-
-
-

*
*
*
*
*

-
-
-

*
*

-
-

*
*
*
*
*
*

-

*
*
*
*
*

---

## 🐛 Troubleshooting

**"Language model did not provide messages"**

- Provider quota exhausted → Check dashboard quota tracker
- Solution: Use combo fallback or switch to cheaper tier

**Rate limiting**

- Subscription quota out → Fallback to GLM/MiniMax
- Add combo: `cc/claude-opus-4-7 → glm/glm-5.1 → kr/claude-sonnet-4.5`

**OAuth token expired**

- Auto-refreshed by 9Router
- If issues persist: Dashboard → Provider → Reconnect

**High costs**

- Enable RTK in Dashboard → Endpoint settings (default ON, saves 20-40% tokens)
- Check usage stats in Dashboard
- Switch primary model to GLM/MiniMax
- Use free tier (Kiro, OpenCode Free, Vertex) for non-critical tasks

**Dashboard opens on wrong port**

- Set `PORT=20128` and `NEXT_PUBLIC_BASE_URL=http://localhost:20128`

**First login not working**

- Check `INITIAL_PASSWORD` in `.env`
- If unset, fallback password is `123456`

**No request logs under `logs/`**

- Set `ENABLE_REQUEST_LOGS=true`

---

## 🛠️ Tech Stack

- **Runtime**: Node.js 20+
- **Framework**: Next.js 16
- **UI**: React 19 + Tailwind CSS 4
- **Database**: SQLite (better-sqlite3 / node\:sqlite / sql.js fallback)
- **Streaming**: Server-Sent Events (SSE)
- **Auth**: OAuth 2.0 (PKCE) + JWT + API Keys

---

## 📝 API Reference

### Chat Completions

```
POST http://localhost:20128/v1/chat/completions
Authorization: Bearer your-api-key
Content-Type: application/json

{
  "model": "cc/claude-opus-4-6",
  "messages": [
    {"role": "user", "content": "Write a function to..."}
  ],
  "stream": true
}
```

### List Models

```
GET http://localhost:20128/v1/models
Authorization: Bearer your-api-key

→ Returns all models + combos in OpenAI format
```

## 📧 Support

- **Website**: [9router.com](https://9router.com)
- **GitHub**: [github.com/decolua/9router](https://github.com/decolua/9router)
- **Issues**: [github.com/decolua/9router/issues](https://github.com/decolua/9router/issues)
