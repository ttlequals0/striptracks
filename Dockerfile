# syntax=docker/dockerfile:1

FROM ghcr.io/linuxserver/baseimage-alpine:3.21

# Read version from VERSION file at build time
COPY VERSION /tmp/VERSION
RUN MOD_VERSION=$(cat /tmp/VERSION | tr -d '[:space:]') && \
  echo "MOD_VERSION=${MOD_VERSION}" > /tmp/build_env
ARG MOD_VERSION=unknown

LABEL org.opencontainers.image.title=striptracks-standalone
LABEL org.opencontainers.image.description="Standalone tool to strip unwanted audio and subtitle tracks from video files"
LABEL org.opencontainers.image.version="${MOD_VERSION}"
LABEL org.opencontainers.image.source="https://github.com/TheCaptain989/radarr-striptracks"
LABEL org.opencontainers.image.licenses=GPL-3.0-only

# Install dependencies
RUN apk add --no-cache \
  mkvtoolnix \
  jq \
  curl \
  bash \
  coreutils \
  inotify-tools

# Copy script and modules
COPY striptracks-standalone.sh /usr/local/bin/striptracks.sh
COPY lib/ /usr/local/bin/lib/
COPY VERSION /usr/local/bin/VERSION
RUN chmod +x /usr/local/bin/striptracks.sh

# Inject version into script
RUN MOD_VERSION=$(cat /usr/local/bin/VERSION | tr -d '[:space:]') && \
  sed -i -e "s/{{VERSION}}/$MOD_VERSION/" /usr/local/bin/lib/cli.sh

ENTRYPOINT ["/usr/local/bin/striptracks.sh"]
