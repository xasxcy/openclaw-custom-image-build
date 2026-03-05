# openclaw-custom-image-build

Custom Docker image build pipeline for [OpenClaw](https://github.com/openclaw/openclaw), adding extra developer tools on top of the official image.

## What this produces

Two container images are automatically built and pushed to GitHub Container Registry:

| Image | Description |
|-------|-------------|
| `ghcr.io/xasxcy/openclaw-tools:latest` | Tool layer: Go, uv, gh, Homebrew, Docker CLI |
| `ghcr.io/xasxcy/openclaw:latest` | Final image: official OpenClaw + all tools above + Chromium |

## Tools included

- **Go** 1.24+ — avoids toolchain auto-download issues in skills
- **uv** — fast Python package manager
- **gh** — GitHub CLI
- **Homebrew** — installed at `/home/linuxbrew/.linuxbrew` (matches OpenClaw's expected path)
- **Docker CLI + Compose plugin** — for Docker-in-Docker workflows
- **Chromium** — via Playwright, for browser automation skills

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
| `Dockerfile.tools` | Both jobs run; tools layer cache is invalidated → **full rebuild** (~15–20 min); final image rebuilds too |
| `Dockerfile` | Both jobs run; tools layer cache hits (fast); **final image rebuilds** |
| `.github/workflows/build.yml` | Both jobs run (full rebuild) |

**Manual** — via the "Run workflow" button in the Actions tab. Chromium installation can be toggled (default: on).

### Chromium in automated builds

Chromium is always installed during scheduled and push-triggered builds. This is controlled by two cooperating parts:

1. **`.github/workflows/build.yml`** — the `Determine install_browser value` step forces `OPENCLAW_INSTALL_BROWSER=1` for any non-manual trigger.
2. **`Dockerfile` lines 185–194** — the `ARG OPENCLAW_INSTALL_BROWSER` + `RUN if [ -n "$OPENCLAW_INSTALL_BROWSER" ]` block performs the actual Playwright Chromium install when the variable is set.

### Image tags

Each build produces two tags per image: `latest` (always updated) and the GitHub Actions run number (immutable, for rollback).

## Build locally

```bash
# Step 1: build the tool layer (only needed when Dockerfile.tools changes)
docker build -f Dockerfile.tools -t openclaw-tools:latest .

# Step 2: build the final image
docker build -t openclaw:local .

# With Chromium support
docker build --build-arg OPENCLAW_INSTALL_BROWSER=1 -t openclaw:local .
```

## Architecture

```
Dockerfile.tools  (base: debian:bookworm-slim)
    └── installs: Go, uv, gh, Homebrew, optional Docker CLI

Dockerfile  (base: ghcr.io/openclaw/openclaw:latest)
    ├── COPY tools from openclaw-tools layer
    ├── installs: Docker CLI, system deps, optional Chromium
    └── final image: openclaw:local / ghcr.io/xasxcy/openclaw:latest
```

## Why a two-stage approach?

The tool layer rarely changes, while the official OpenClaw image updates frequently. By separating them, the slow tool installation (especially Homebrew) only runs when tools actually change, keeping CI build times short.
