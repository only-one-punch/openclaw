FROM node:22-bookworm

# Install Bun (required for build scripts)
RUN curl -fsSL https://bun.sh/install | bash
ENV PATH="/root/.bun/bin:${PATH}"

RUN corepack enable

WORKDIR /app

ARG OPENCLAW_DOCKER_APT_PACKAGES=""
RUN if [ -n "$OPENCLAW_DOCKER_APT_PACKAGES" ]; then \
      apt-get update && \
      DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends $OPENCLAW_DOCKER_APT_PACKAGES && \
      apt-get clean && \
      rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/*; \
    fi

COPY package.json pnpm-lock.yaml pnpm-workspace.yaml .npmrc ./
COPY ui/package.json ./ui/package.json
COPY patches ./patches
COPY scripts ./scripts

RUN pnpm install --frozen-lockfile

COPY . .
RUN pnpm build
# Force pnpm for UI build (Bun may fail on ARM/Synology architectures)
ENV OPENCLAW_PREFER_PNPM=1
RUN pnpm ui:build

ENV NODE_ENV=production

# Allow non-root user to write temp files during runtime/tests.
RUN chown -R node:node /app
# Ensure the volume mount point is writable by the non-root user (Railway, Render, etc.)
RUN mkdir -p /data && chown -R node:node /data

# Install gosu for dropping privileges in entrypoint, and Chromium for browser tools
RUN apt-get update && apt-get install -y --no-install-recommends \
      gosu \
      chromium \
      fonts-liberation \
      fonts-noto-color-emoji \
      libxss1 \
      xdg-utils \
    && rm -rf /var/lib/apt/lists/*

ENV PUPPETEER_SKIP_CHROMIUM_DOWNLOAD=true

COPY chromium-docker-wrapper.sh /usr/local/bin/chromium-docker-wrapper
RUN chmod +x /usr/local/bin/chromium-docker-wrapper

COPY docker-entrypoint.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

ENTRYPOINT ["docker-entrypoint.sh"]

# Start gateway server with default config.
# Binds to loopback (127.0.0.1) by default for security.
#
# IMPORTANT: PaaS platforms (Railway, Render, etc.) that override the start
# command via their own config (e.g. railway.json startCommand) will bypass
# this ENTRYPOINT unless the start command explicitly invokes
# docker-entrypoint.sh. See railway.json for the correct pattern.
#
# For container platforms requiring external health checks:
#   1. Set OPENCLAW_GATEWAY_TOKEN or OPENCLAW_GATEWAY_PASSWORD env var
#   2. Override CMD: ["node","openclaw.mjs","gateway","--allow-unconfigured","--bind","lan"]
CMD ["node", "openclaw.mjs", "gateway", "--allow-unconfigured"]
