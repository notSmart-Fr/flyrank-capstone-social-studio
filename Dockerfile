# Step 1: Build stage
FROM hexpm/elixir:1.20.4-erlang-29.0-alpine-3.22.0 AS build

RUN apk add --no-cache build-base git nodejs npm

WORKDIR /app

RUN mix local.hex --force && \
    mix local.rebar --force

ENV MIX_ENV=dev

COPY mix.exs mix.lock ./
RUN mix deps.get
RUN mix deps.compile

COPY config config
COPY lib lib
COPY priv priv
COPY assets assets

RUN mix assets.deploy

ENV MIX_ENV=prod

RUN mix compile
RUN mix release

# Step 2: Runtime stage
FROM alpine:3.19.1 AS app

RUN apk add --no-cache libstdc++ ncurses-libs openssl libgcc

WORKDIR /app

COPY --from=build /app/_build/prod/rel/flyrank_capstone_social_studio ./

ENV HOME=/app
ENV MIX_ENV=prod

EXPOSE 4000

CMD ["bin/flyrank_capstone_social_studio", "start"]