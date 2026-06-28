FROM elixir:1.18-slim AS dev

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    ca-certificates \
    curl \
    git \
    inotify-tools \
    postgresql-client \
  && rm -rf /var/lib/apt/lists/*

WORKDIR /app

RUN mix local.hex --force && mix local.rebar --force

ENV MIX_HOME=/root/.mix \
    HEX_HOME=/root/.hex \
    LANG=C.UTF-8

EXPOSE 4000

CMD ["./bin/control-panel"]

FROM dev AS build

ENV MIX_ENV=prod

COPY mix.exs mix.lock ./
RUN mix deps.get --only prod

RUN mkdir config
COPY config/config.exs config/prod.exs config/
RUN mix deps.compile

COPY priv priv
COPY lib lib
COPY assets assets
RUN mix assets.deploy

COPY config/runtime.exs config/
COPY rel rel
RUN mix release

FROM debian:trixie-slim AS release

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    libncurses6 \
    libstdc++6 \
    locales \
    openssl \
  && sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen \
  && locale-gen \
  && rm -rf /var/lib/apt/lists/*

WORKDIR /app

ENV MIX_ENV=prod \
    HOME=/app \
    LANG=en_US.UTF-8 \
    LANGUAGE=en_US:en \
    LC_ALL=en_US.UTF-8

COPY --from=build /app/_build/prod/rel/andnative_ai ./

RUN mkdir -p /app/var/sources /app/var/openclaw

EXPOSE 4000

CMD ["./bin/control-panel"]
