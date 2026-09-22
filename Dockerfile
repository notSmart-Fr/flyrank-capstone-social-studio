ARG ELIXIR_VERSION=1.20.4
ARG OTP_VERSION=29.0.6
ARG DEBIAN_VERSION=trixie-20260824-slim

ARG BUILDER_IMAGE="docker.io/hexpm/elixir:${ELIXIR_VERSION}-erlang-${OTP_VERSION}-debian-${DEBIAN_VERSION}"
ARG RUNNER_IMAGE="docker.io/debian:${DEBIAN_VERSION}"

FROM ${BUILDER_IMAGE} AS builder

# Install build dependencies
RUN apt-get update \
  && apt-get install -y --no-install-recommends build-essential git nodejs npm \
  && rm -rf /var/lib/apt/lists/*

# Prepare build dir
WORKDIR /app

# Install hex + rebar
RUN mix local.hex --force \
  && mix local.rebar --force

# Set build ENV
ENV MIX_ENV="prod"

# Install mix dependencies
COPY mix.exs mix.lock ./
RUN mix deps.get --only $MIX_ENV
RUN mkdir config

# Copy compile-time config files
COPY config/config.exs config/${MIX_ENV}.exs config/
RUN mix deps.compile

# Setup mix asset tools (esbuild / tailwind CLI)
RUN mix assets.setup

# Install npm dependencies if package.json exists
COPY assets/package.json assets/package-lock.json assets/
RUN npm ci --prefix assets

# Copy code application files and assets
COPY priv priv
COPY lib lib
COPY assets assets

# Compile application code
RUN mix compile

# Compile assets (now has access to /app/deps and /app/assets)
RUN mix assets.deploy

# Copy runtime config and release setup
COPY config/runtime.exs config/
COPY rel rel
RUN mix release

# -----------------------------------------------------------------------------
# Final Runner Stage
# -----------------------------------------------------------------------------
FROM ${RUNNER_IMAGE} AS final

RUN apt-get update \
  && apt-get install -y --no-install-recommends libstdc++6 openssl libncurses6 locales ca-certificates \
  && rm -rf /var/lib/apt/lists/*

# Set locale
RUN sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen \
  && locale-gen

ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US:en
ENV LC_ALL=en_US.UTF-8

WORKDIR "/app"
RUN chown nobody /app

ENV MIX_ENV="prod"

# Copy compiled release
COPY --from=builder --chown=nobody:root /app/_build/${MIX_ENV}/rel/flyrank_capstone_social_studio ./

USER nobody

CMD ["/app/bin/server"]