FROM elixir:1.18-slim

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
