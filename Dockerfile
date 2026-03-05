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

# ── Docker CLI（两种烘焙位置，二选一）─────────────────────────────────────────
#
# 只能启用下面两种方式中的一种，否则你会：
#   - 两边都装：镜像变大，构建变慢，还会混淆“到底用的是哪套 docker”
#   - 两边都不装：容器里没有 docker 命令
#
# 方式 A：在 tools 镜像里烘焙 Docker CLI，然后在这里 COPY 进来
# 好处：
#   - 最终镜像构建更快（不需要跑 Docker apt 源与安装）
#   - docker CLI 变成你工具层的一部分，多个最终镜像复用
# 坏处：
#   - tools 镜像需要更频繁更新（跟随 docker CLI 版本）
#   - tools 与官方 openclaw 基础发行版需要保持兼容，否则可能出现依赖不匹配
#
# 启用 A 的做法：
#   1) 构建 tools 时加：--build-arg 取消注释对应 RUN 块
#   2) 取消下面三行 COPY 的注释
#   3) 保持方式 B 不启用（保持方式 B 的安装块为注释状态）
#
# COPY --from=tools /usr/bin/docker /usr/bin/docker
# COPY --from=tools /usr/libexec/docker /usr/libexec/docker
# COPY --from=tools /usr/lib/docker /usr/lib/docker
#
# 方式 B：在最终镜像里安装 Docker CLI（不依赖 tools）
# 好处：
#   - tools 镜像更稳定，更新频率更低
#   - 更贴近官方 Dockerfile 的做法，排障更简单
# 坏处：
#   - 最终镜像 build 会更慢（每次都要跑 Docker apt 源与安装）
#
# 启用 B 的做法：
#   1) 构建最终镜像时加：--build-arg 取消注释对应 RUN 块
#   2) 保持方式 A 的 COPY 注释状态
#
# 方式 B：在最终镜像里安装 Docker CLI（不依赖 tools）
# 好处：
#   - tools 镜像更稳定，更新频率更低
#   - 更贴近官方 Dockerfile 的做法，排障更简单
# 坏处：
#   - 最终镜像 build 会更慢（每次都要跑 Docker apt 源与安装）
#
# 只能启用两处中的一个：要么在 Dockerfile.tools 里安装，要么在这里安装。
#
# 启用方式：
#   1) 取消下面 RUN 块的注释
#   2) 保持方式 A 的 COPY 为注释状态
#   3) 保持 Dockerfile.tools 里的 Docker 安装块为注释状态
ARG OPENCLAW_DOCKER_GPG_FINGERPRINT="9DC858229FC7DD38854AE2D88D81803C0EBFCD88"

RUN apt-get update \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends ca-certificates curl gnupg \
 && install -m 0755 -d /etc/apt/keyrings \
 && curl -fsSL https://download.docker.com/linux/debian/gpg -o /tmp/docker.gpg.asc \
 && expected_fingerprint="$(printf '%s' "$OPENCLAW_DOCKER_GPG_FINGERPRINT" | tr '[:lower:]' '[:upper:]' | tr -d '[:space:]')" \
 && actual_fingerprint="$(gpg --batch --show-keys --with-colons /tmp/docker.gpg.asc | awk -F: '$1 == "fpr" { print toupper($10); exit }')" \
 && if [ -z "$actual_fingerprint" ] || [ "$actual_fingerprint" != "$expected_fingerprint" ]; then \
      echo "ERROR: Docker apt key fingerprint mismatch (expected $expected_fingerprint, got ${actual_fingerprint:-})" >&2; \
      exit 1; \
    fi \
 && gpg --dearmor -o /etc/apt/keyrings/docker.gpg /tmp/docker.gpg.asc \
 && rm -f /tmp/docker.gpg.asc \
 && chmod a+r /etc/apt/keyrings/docker.gpg \
 && printf 'deb [arch=%s signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian bookworm stable\n' \
      "$(dpkg --print-architecture)" > /etc/apt/sources.list.d/docker.list \
 && apt-get update \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends docker-ce-cli docker-compose-plugin \
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

# ── npm 全局目录权限 ──────────────────────────────────────────────────────────
RUN chown -R node:node /usr/local/lib/node_modules 2>/dev/null || true

USER node
