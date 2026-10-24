# ========================================================
# Stage: Frontend (Vite)
# ========================================================
FROM --platform=$BUILDPLATFORM node:26-alpine AS frontend
WORKDIR /src/frontend
COPY frontend/package.json frontend/package-lock.json ./
RUN npm ci
COPY frontend/ ./
COPY internal/web/translation /src/internal/web/translation
RUN npm run build

# ========================================================
# Stage: Builder (Cross-compiled on native $BUILDPLATFORM)
# ========================================================
FROM --platform=$BUILDPLATFORM golang:1.27 AS builder
WORKDIR /app

RUN apt-get update && apt-get install -y --no-install-recommends \
  unzip \
  xz-utils \
  && rm -rf /var/lib/apt/lists/*

COPY go.mod go.sum ./
RUN go mod download

COPY . .
COPY --from=frontend /src/internal/web/dist ./internal/web/dist

ARG BUILDARCH
ARG TARGETARCH
ARG TARGETVARIANT

RUN set -e; \
  CURL_RETRY="--retry 5 --retry-all-errors --retry-delay 3 --connect-timeout 15"; \
  export CGO_ENABLED=1; \
  export CGO_CFLAGS="-D_LARGEFILE64_SOURCE"; \
  export GOOS=linux; \
  case "${TARGETARCH}/${TARGETVARIANT}" in \
    amd64/*) INIT_ARCH="amd64"; BOOTLIN_ARCH="x86-64"; export GOARCH=amd64 ;; \
    arm64/*) INIT_ARCH="arm64"; BOOTLIN_ARCH="aarch64"; export GOARCH=arm64 ;; \
    arm/v7|arm/) INIT_ARCH="armv7"; BOOTLIN_ARCH="armv7-eabihf"; export GOARCH=arm GOARM=7 ;; \
    arm/v6) INIT_ARCH="armv6"; BOOTLIN_ARCH="armv6-eabihf"; export GOARCH=arm GOARM=6 ;; \
    386/*) INIT_ARCH="386"; BOOTLIN_ARCH="x86-i686"; export GOARCH=386 ;; \
    *) echo "Unsupported target platform: ${TARGETARCH}/${TARGETVARIANT}" >&2; exit 1 ;; \
  esac; \
  if [ "$BUILDARCH" = "amd64" ]; then \
    TARBALL_BASE="https://toolchains.bootlin.com/downloads/releases/toolchains/$BOOTLIN_ARCH/tarballs/"; \
    TARBALL_URL=$(curl -fsSL $CURL_RETRY "$TARBALL_BASE" | grep -oE "${BOOTLIN_ARCH}--musl--stable-[^\"]+\\.tar\\.xz" | sort -r | head -n1); \
    [ -z "$TARBALL_URL" ] && { echo "Failed to locate Bootlin musl toolchain for arch=$BOOTLIN_ARCH" >&2; exit 1; }; \
    mkdir -p /tmp/toolchain && cd /tmp/toolchain; \
    curl -fL -sS $CURL_RETRY -o toolchain.tar.xz "$TARBALL_BASE/$TARBALL_URL"; \
    tar -xf toolchain.tar.xz; \
    TOOLCHAIN_DIR=$(find . -maxdepth 1 -type d -name "${BOOTLIN_ARCH}--musl--stable-*" | head -n1); \
    export PATH="$(realpath "$TOOLCHAIN_DIR")/bin:$PATH"; \
    export CC=$(realpath "$(find "$TOOLCHAIN_DIR/bin" -name '*-gcc.br_real' -type f -executable | head -n1)"); \
    [ -z "$CC" ] && { echo "No gcc.br_real found in $TOOLCHAIN_DIR/bin" >&2; exit 1; }; \
    cd /app; \
  fi; \
  if go list -f '{{join .GoFiles "\n"}}' ./internal/web/service/panel | grep -q '^sponsor\.go$'; then \
    echo "Sponsor backend must not be compiled into fork releases" >&2; \
    exit 1; \
  fi; \
  mkdir -p build; \
  go build -ldflags "-w -s -linkmode external -extldflags '-static'" -o build/x-ui main.go; \
  rm -rf /tmp/toolchain; \
  chmod +x ./DockerInit.sh; \
  ./DockerInit.sh "$INIT_ARCH"

# ========================================================
# Stage: Final Image of 3x-ui
# ========================================================
FROM alpine
ENV TZ=Asia/Tehran
WORKDIR /app

RUN apk add --no-cache --update \
  ca-certificates \
  tzdata \
  fail2ban \
  bash \
  curl \
  openssl

COPY --from=builder /app/build/ /app/
COPY --from=builder /app/DockerEntrypoint.sh /app/
COPY --from=builder /app/x-ui.sh /usr/bin/x-ui
COPY --from=builder /app/internal/web/translation /app/internal/web/translation

# Configure fail2ban
RUN rm -f /etc/fail2ban/jail.d/alpine-ssh.conf \
  && cp /etc/fail2ban/jail.conf /etc/fail2ban/jail.local \
  && sed -i "s/^\[ssh\]$/&\nenabled = false/" /etc/fail2ban/jail.local \
  && sed -i "s/^\[sshd\]$/&\nenabled = false/" /etc/fail2ban/jail.local \
  && sed -i "s/#allowipv6 = auto/allowipv6 = auto/g" /etc/fail2ban/fail2ban.conf

RUN chmod +x \
  /app/DockerEntrypoint.sh \
  /app/x-ui \
  /usr/bin/x-ui

ENV XUI_IN_DOCKER="true"
ENV XUI_MAIN_FOLDER="/app"
ENV XUI_ENABLE_FAIL2BAN="true"
ENV XUI_DB_TYPE=""
ENV XUI_DB_DSN=""
EXPOSE 2053
VOLUME [ "/etc/x-ui" ]
CMD [ "./x-ui" ]
ENTRYPOINT [ "/app/DockerEntrypoint.sh" ]
