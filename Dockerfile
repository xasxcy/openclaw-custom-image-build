# ── Wrapper Dockerfile ───────────────────────────────────────────────────────
# 基于官方预构建镜像，从 openclaw-tools 复制工具层，跳过重复安装。
#
# 构建顺序：
#   1. docker build -f Dockerfile.tools -t openclaw-tools:latest .   （工具层，变动时才重新 build）
#   2. docker pull ghcr.io/openclaw/openclaw:latest                  （跟进官方版本）
#   3. docker build -f Dockerfile -t openclaw:local .                （最终镜像，速度快）
#
# 基础镜像：latest = 最新正式版，如需锁定版本替换为：
#   FROM ghcr.io/openclaw/openclaw:2026.2.26
# ─────────────────────────────────────────────────────────────────────────────
FROM ghcr.io/xasxcy/openclaw-tools:latest AS tools
FROM ghcr.io/openclaw/openclaw:latest

USER root

# ── 从工具层复制 ──────────────────────────────────────────────────────────────
# Go
COPY --from=tools /usr/local/go /usr/local/go
RUN ln -sf /usr/local/go/bin/go /usr/local/bin/go && \
    ln -sf /usr/local/go/bin/gofmt /usr/local/bin/gofmt
ENV PATH="/usr/local/go/bin:${PATH}"
ENV GOPATH="/home/node/go"
RUN mkdir -p /home/node/go && chown -R node:node /home/node/go

# uv
COPY --from=tools /usr/local/bin/uv /usr/local/bin/uv

# gh
COPY --from=tools /usr/bin/gh /usr/bin/gh

# ── Docker CLI ────────────────────────────────────────────────────────────────
# Installed here rather than in the tools layer, so the tools layer stays stable.
# DOCKER_CLI_VERSION: pin to a specific release (e.g. 27.3.1); leave unset for latest.
ARG DOCKER_CLI_VERSION=""

RUN apt-get update \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends ca-certificates curl \
 && install -m 0755 -d /etc/apt/keyrings \
 && curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc \
 && chmod a+r /etc/apt/keyrings/docker.asc \
 && printf 'deb [arch=%s signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian bookworm stable\n' \
      "$(dpkg --print-architecture)" > /etc/apt/sources.list.d/docker.list \
 && apt-get update \
 && if [ -n "$DOCKER_CLI_VERSION" ]; then \
      CLI_VER=$(apt-cache madison docker-ce-cli | awk -v v="$DOCKER_CLI_VERSION" '$0 ~ v {print $3; exit}'); \
      DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "docker-ce-cli=${CLI_VER}" docker-compose-plugin; \
    else \
      DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends docker-ce-cli docker-compose-plugin; \
    fi \
 && apt-get clean \
 && rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/*

# Homebrew
COPY --from=tools /home/linuxbrew /home/linuxbrew
RUN chown -R node:node /home/linuxbrew
RUN ln -sf /home/linuxbrew/.linuxbrew/bin/brew /usr/local/bin/brew
ENV PATH="/home/linuxbrew/.linuxbrew/bin:/home/linuxbrew/.linuxbrew/sbin:${PATH}"
ENV HOMEBREW_PREFIX="/home/linuxbrew/.linuxbrew"
ENV HOMEBREW_CELLAR="/home/linuxbrew/.linuxbrew/Cellar"
ENV HOMEBREW_REPOSITORY="/home/linuxbrew/.linuxbrew/Homebrew"
RUN mkdir -p /home/node/.cache/Homebrew && chown -R node:node /home/node/.cache
# 将 Homebrew 路径写入 /etc/profile.d，确保所有交互式 shell（包括 node 用户）
# 启动时无需手动 export，brew.sh 内部路径查找也能正常工作
RUN printf 'export PATH="/home/linuxbrew/.linuxbrew/bin:/home/linuxbrew/.linuxbrew/sbin:$PATH"\n\
export HOMEBREW_PREFIX="/home/linuxbrew/.linuxbrew"\n\
export HOMEBREW_CELLAR="/home/linuxbrew/.linuxbrew/Cellar"\n\
export HOMEBREW_REPOSITORY="/home/linuxbrew/.linuxbrew/Homebrew"\n' \
    > /etc/profile.d/homebrew.sh && \
    chmod 644 /etc/profile.d/homebrew.sh

# 系统依赖（apt 无法跨镜像复制，直接安装）
RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      apt-utils \
      socat \
      ffmpeg \
      build-essential \
      git \
      curl \
      jq \
      python3 \
      file \
      procps \
      ca-certificates \
      libgbm1 \
      libnss3 \
      libatk1.0-0 \
      libatk-bridge2.0-0 \
      libcups2 \
      libdrm2 \
      libxkbcommon0 \
      libxcomposite1 \
      libxdamage1 \
      libxfixes3 \
      libxrandr2 \
      libpango-1.0-0 \
      libcairo2 \
      libasound2 \
      libx11-6 \
      libx11-xcb1 \
      libxcb1 \
      libxext6 \
      fonts-liberation \
      libappindicator3-1 \
      xdg-utils \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/*

# python → python3 软链（部分 skill 调用裸 python 命令）
RUN ln -sf /usr/bin/python3 /usr/local/bin/python

# 将 /bin/sh 指向 bash，避免 source 命令在 dash 下报错
RUN ln -sf /bin/bash /bin/sh

# ── Hetzner 文档推荐的外部二进制文件 ────────────────────────────────────────
# gog：Gmail CLI（Google OAuth Gateway）
# RUN curl -L https://github.com/steipete/gog/releases/latest/download/gog_Linux_x86_64.tar.gz \
#     | tar -xz -C /usr/local/bin && chmod +x /usr/local/bin/gog

# goplaces：Google Places CLI
# RUN curl -L https://github.com/steipete/goplaces/releases/latest/download/goplaces_Linux_x86_64.tar.gz \
#     | tar -xz -C /usr/local/bin && chmod +x /usr/local/bin/goplaces

# wacli：WhatsApp CLI
# RUN curl -L https://github.com/steipete/wacli/releases/latest/download/wacli_Linux_x86_64.tar.gz \
#     | tar -xz -C /usr/local/bin && chmod +x /usr/local/bin/wacli

# ── Chromium --no-sandbox 环境变量 ───────────────────────────────────────────
ENV CHROMIUM_FLAGS="--no-sandbox --disable-setuid-sandbox"
ENV PLAYWRIGHT_CHROMIUM_EXECUTABLE_FLAGS="--no-sandbox --disable-setuid-sandbox"
# 持久写入 PLAYWRIGHT_BROWSERS_PATH，使运行时 OpenClaw 能直接定位浏览器，
# 无需在容器启动脚本里额外 export。路径与 Playwright 自身默认值（~/.cache/ms-playwright）对齐。
ENV PLAYWRIGHT_BROWSERS_PATH="/home/node/.cache/ms-playwright"

# ── Chromium 可选安装（需 build arg）────────────────────────────────────────
# docker build --build-arg OPENCLAW_INSTALL_BROWSER=1 ...
ARG OPENCLAW_INSTALL_BROWSER=""
RUN if [ -n "$OPENCLAW_INSTALL_BROWSER" ]; then \
      apt-get update && \
      DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends xvfb && \
      mkdir -p /home/node/.cache/ms-playwright && \
      node /app/node_modules/playwright-core/cli.js install --with-deps chromium && \
      chown -R node:node /home/node/.cache/ms-playwright && \
      apt-get clean && \
      rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/*; \
    fi

# ── 补装官方镜像缺失的扩展依赖（待上游修复后移除）────────────────────────────
# https://github.com/openclaw/openclaw/issues/23611
RUN cd /tmp && npm init -y && npm install @larksuiteoapi/node-sdk && \
    rm -rf /app/node_modules/@larksuiteoapi && \
    cp -r node_modules/@larksuiteoapi /app/node_modules/ && \
    ls /app/node_modules/@larksuiteoapi/node-sdk/package.json && \
    rm -rf /tmp/package.json /tmp/node_modules /tmp/package-lock.json

# ── npm 全局目录权限 ──────────────────────────────────────────────────────────
RUN chown -R node:node /usr/local/lib/node_modules 2>/dev/null || true

USER node
