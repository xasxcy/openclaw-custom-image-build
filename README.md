# openclaw-custom-image-build

Custom Docker image build pipeline for [OpenClaw](https://github.com/openclaw/openclaw), adding extra developer tools on top of the official image.

## What this produces

Two container images are automatically built and pushed to GitHub Container Registry:

| Image | Description |
|-------|-------------|
| `ghcr.io/xasxcy/openclaw-tools:latest` | Tool layer: Go, uv/uvx, gh, cloudflared, Homebrew |
| `ghcr.io/xasxcy/openclaw:latest` | Final image: official OpenClaw + all tools + Docker CLI + Chromium + browser-use |

## Tools included

- **Go** 1.24+ — avoids toolchain auto-download issues in skills
- **uv / uvx** — fast Python package manager and tool runner
- **gh** — GitHub CLI
- **cloudflared** — Cloudflare Tunnel CLI
- **Homebrew** — installed at `/home/linuxbrew/.linuxbrew` (matches OpenClaw's expected path)
- **Docker CLI + Compose plugin** — for Docker-in-Docker workflows
- **python3 + pip** — system Python with pip available for interactive use
- **browser-use** — Python library for AI browser automation (installed via uv)
- **Chromium** — via Playwright, installed to `/usr/local/ms-playwright`; symlinked to `/usr/bin/chromium`, `/usr/bin/chromium-browser`, `/usr/bin/google-chrome-stable`

## How to use the built image

Pull the latest image:

```bash
docker pull ghcr.io/xasxcy/openclaw:latest
```

In your `docker-compose.yml`, replace the official image with this one:

```yaml
services:
  openclaw-gateway:
    image: ghcr.io/xasxcy/openclaw:latest
```

## Automated builds

### Triggers

**Scheduled — daily at 02:00 UTC**

Both jobs run every day. The tools layer hits the registry cache (fast) since `Dockerfile.tools` rarely changes. The final image re-pulls `ghcr.io/openclaw/openclaw:latest` and rebuilds if there is a new upstream release.

**On push to `main`** — only when these files change (other files like README do not trigger a build):

| File changed | What happens |
|---|---|
| `Dockerfile.tools` | Both jobs run; tools layer cache is invalidated → **full rebuild**; final image rebuilds too |
| `Dockerfile` | Both jobs run; tools layer cache hits (fast); **final image rebuilds** |
| `.github/workflows/build.yml` | Both jobs run (full rebuild) |

**Manual** — via the "Run workflow" button in the Actions tab.

### Chromium

Chromium is **always installed** unconditionally. Playwright downloads it to `/usr/local/ms-playwright` (a stable system path, not a user cache directory), and the build creates symlinks at standard system paths so tools that look for `google-chrome-stable`, `chromium`, or `chromium-browser` will find it.

### Image tags

Each build produces two tags per image: `latest` (always updated) and a date tag (e.g. `:20260416`, immutable, for rollback).

## Build locally

```bash
# Step 1: build the tool layer (only needed when Dockerfile.tools changes)
docker build -f Dockerfile.tools -t openclaw-tools:latest .

# Step 2: build the final image
docker build -t openclaw:local .
```

## Architecture

```
Dockerfile.tools  (base: debian:bookworm-slim)
    └── installs: Go, uv/uvx, gh, cloudflared, Homebrew

Dockerfile  (base: ghcr.io/openclaw/openclaw:latest)
    ├── COPY tools from openclaw-tools layer
    ├── installs: Docker CLI, system deps (incl. python3-pip), browser-use
    ├── installs: Playwright Chromium → /usr/local/ms-playwright
    ├── symlinks: /usr/bin/chromium, chromium-browser, google-chrome-stable
    └── final image: openclaw:local / ghcr.io/xasxcy/openclaw:latest
```

## Why a two-stage approach?

The tool layer rarely changes, while the official OpenClaw image updates frequently. By separating them, the slow tool installation (especially Homebrew) only runs when tools actually change, keeping CI build times short.
