# syntax=docker/dockerfile:1.7
# ZeroClaw – Gemini provider variant
# Built from the Homebrew formula source tarball — no local repo clone required.
#
# Build:
#   docker build -t neuron-zeroclaw-gemini .
#
# Run:
#   docker run -d \
#     --name neuron-zeroclaw \
#     -p 42617:42617 \
#     -v zeroclaw_data:/zeroclaw-data \
#     -e TELEGRAM_BOT_TOKEN=123456:ABC... \
#     -e GEMINI_API_KEY=your-gemini-key \
#     -e BRAVE_API_KEY=your-brave-key \
#     neuron-zeroclaw-gemini
#
# First run: the bot logs a /bind <code> pairing code.
# Send that command to the bot in Telegram to whitelist your user ID.

ARG ZEROCLAW_VERSION=0.1.6
# SHA256 of the source tarball — matches the Homebrew formula.
ARG ZEROCLAW_SHA256=e4536eafb945e1a80ce6616197521a0be3267075ac9916be45232ba7448989d9

# ── Stage 1: Build ────────────────────────────────────────────
FROM rust:1.93-slim@sha256:9663b80a1621253d30b146454f903de48f0af925c967be48c84745537cd35d8b AS builder

ARG ZEROCLAW_VERSION
ARG ZEROCLAW_SHA256

WORKDIR /build

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get update && apt-get install -y \
        curl \
        pkg-config \
    && rm -rf /var/lib/apt/lists/*

# Download the same tarball Homebrew uses, verify checksum, extract.
RUN curl -fsSL \
        "https://github.com/zeroclaw-labs/zeroclaw/archive/refs/tags/v${ZEROCLAW_VERSION}.tar.gz" \
        -o zeroclaw.tar.gz && \
    echo "${ZEROCLAW_SHA256}  zeroclaw.tar.gz" | sha256sum -c && \
    tar -xzf zeroclaw.tar.gz --strip-components=1 && \
    rm zeroclaw.tar.gz

# Build — cargo layer cache is shared across rebuilds.
RUN --mount=type=cache,id=zeroclaw-cargo-registry,target=/usr/local/cargo/registry,sharing=locked \
    --mount=type=cache,id=zeroclaw-cargo-git,target=/usr/local/cargo/git,sharing=locked \
    --mount=type=cache,id=zeroclaw-target,target=/build/target,sharing=locked \
    cargo build --release --locked && \
    cp target/release/zeroclaw /usr/local/bin/zeroclaw && \
    strip /usr/local/bin/zeroclaw

RUN mkdir -p /zeroclaw-data/.zeroclaw /zeroclaw-data/workspace && \
    chown -R 65534:65534 /zeroclaw-data

# ── Stage 2: Runtime (Debian slim) ───────────────────────────
# Distroless is skipped because the Telegram bot_token must be written into
# config.toml at startup by an entrypoint shell script.
FROM debian:trixie-slim@sha256:f6e2cfac5cf956ea044b4bd75e6397b4372ad88fe00908045e9a0d21712ae3ba AS release

RUN apt-get update && apt-get install -y \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

COPY --from=builder /usr/local/bin/zeroclaw /usr/local/bin/zeroclaw
COPY --from=builder /zeroclaw-data /zeroclaw-data

# Entrypoint: uses zeroclaw onboard to generate a proper full config, then
# appends only the Telegram section (the only thing not settable via env vars).
# Preserves allowed_users so Telegram pairing survives restarts.
RUN cat > /entrypoint.sh <<'SCRIPT'
#!/bin/sh
set -e
: "${TELEGRAM_BOT_TOKEN:?TELEGRAM_BOT_TOKEN is required}"
CONFIG=/zeroclaw-data/.zeroclaw/config.toml
mkdir -p "$(dirname "$CONFIG")"

# Preserve paired Telegram user IDs across restarts
ALLOWED_USERS="[]"
if [ -f "$CONFIG" ]; then
    line=$(grep "^allowed_users = " "$CONFIG" 2>/dev/null || true)
    [ -n "$line" ] && ALLOWED_USERS="${line#allowed_users = }"
fi

# Generate a proper full config via zeroclaw's own onboard command.
# ZEROCLAW_CONFIG_DIR is already set so it writes to the right place.
zeroclaw onboard --provider gemini --model gemini-2.5-flash --force

# Inject API keys — onboard leaves them blank; zeroclaw reads from config, not env.
if [ -n "$GEMINI_API_KEY" ]; then
    sed -i "s|^api_key = .*|api_key = \"$GEMINI_API_KEY\"|" "$CONFIG"
fi
if [ -n "$BRAVE_API_KEY" ]; then
    sed -i "s|^brave_api_key = .*|brave_api_key = \"$BRAVE_API_KEY\"|" "$CONFIG"
fi

# Expose gateway on all interfaces so Docker port mapping works.
# Patch the [gateway] section written by onboard — duplicate TOML sections are ignored.
sed -i '/^\[gateway\]/,/^\[/{s/^host = .*/host = "[::]"/}' "$CONFIG"
grep -q '^host = ' "$CONFIG" || sed -i '/^\[gateway\]/a host = "[::]"' "$CONFIG"
sed -i '/^\[gateway\]/,/^\[/{s/^allow_public_bind = .*/allow_public_bind = true/}' "$CONFIG"
grep -q '^allow_public_bind = ' "$CONFIG" || sed -i '/^\[gateway\]/a allow_public_bind = true' "$CONFIG"

# Append Telegram channel — onboard doesn't include it and bot_token
# has no env var override in the config loader.
cat >> "$CONFIG" <<EOF

[channels_config.telegram]
bot_token = "$TELEGRAM_BOT_TOKEN"
allowed_users = $ALLOWED_USERS
EOF

exec zeroclaw "$@"
SCRIPT
RUN chmod +x /entrypoint.sh && chown 65534:65534 /entrypoint.sh

ENV HOME=/zeroclaw-data
# Pin config dir — highest-priority, bypasses all workspace-based path resolution
ENV ZEROCLAW_CONFIG_DIR=/zeroclaw-data/.zeroclaw
ENV ZEROCLAW_WORKSPACE=/zeroclaw-data/workspace
# PROVIDER is the canonical env var (ZEROCLAW_PROVIDER kept for compatibility)
ENV PROVIDER="gemini"
ENV ZEROCLAW_PROVIDER="gemini"
ENV ZEROCLAW_MODEL="gemini-2.5-flash"
ENV ZEROCLAW_GATEWAY_PORT=42617
ENV ZEROCLAW_ALLOW_PUBLIC_BIND=true
ENV WEB_SEARCH_ENABLED=true
ENV WEB_SEARCH_PROVIDER="brave"

# Secrets must be injected at runtime — never bake them into the image.
# Required:  TELEGRAM_BOT_TOKEN
# Optional:  GEMINI_API_KEY, BRAVE_API_KEY

WORKDIR /zeroclaw-data
USER 65534:65534
EXPOSE 42617
ENTRYPOINT ["/entrypoint.sh"]
CMD ["daemon"]
