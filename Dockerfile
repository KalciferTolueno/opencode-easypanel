FROM node:24-bookworm-slim

ARG OPENCODE_NPM_PACKAGE=opencode-ai

ENV HOME=/home/opencode \
    XDG_CONFIG_HOME=/home/opencode/.config \
    XDG_DATA_HOME=/home/opencode/.local/share \
    XDG_STATE_HOME=/home/opencode/.local/state \
    XDG_CACHE_HOME=/home/opencode/.cache \
    PATH=/home/opencode/.local/bin:${PATH}

RUN apt-get update \
    && apt-get install --no-install-recommends -y \
        bash \
        build-essential \
        ca-certificates \
        curl \
        git \
        openssh-client \
        python3 \
        python3-pip \
    && npm install --global "${OPENCODE_NPM_PACKAGE}" pnpm \
    && npm cache clean --force \
    && useradd --create-home --home-dir /home/opencode --shell /bin/bash opencode \
    && install --directory --owner=opencode --group=opencode --mode=0750 \
        /workspace \
        /home/opencode/.config/opencode \
        /home/opencode/.local/share/opencode \
        /home/opencode/.local/state/opencode \
        /home/opencode/.cache/opencode \
        /home/opencode/.ssh \
    && rm -rf /var/lib/apt/lists/*

USER opencode
WORKDIR /workspace

EXPOSE 4096

HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=3 \
  CMD curl --fail --silent --show-error \
    --user "$OPENCODE_SERVER_USERNAME:$OPENCODE_SERVER_PASSWORD" \
    http://127.0.0.1:4096/global/health > /dev/null || exit 1

CMD ["opencode", "web", "--hostname", "0.0.0.0", "--port", "4096"]
