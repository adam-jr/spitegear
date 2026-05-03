FROM hexpm/elixir:1.18.4-erlang-28.0.2-debian-bullseye-20260421-slim AS builder

RUN apt-get update -y && apt-get install -y build-essential git \
    && apt-get clean && rm -f /var/lib/apt/lists/*_*

WORKDIR /app

RUN mix local.hex --force && mix local.rebar --force

ENV MIX_ENV=prod

COPY mix.exs mix.lock ./
RUN mix deps.get --only prod

COPY config/config.exs config/prod.exs config/runtime.exs config/
RUN mix deps.compile

COPY priv priv
COPY lib lib
COPY assets assets
COPY rel rel

RUN mix assets.deploy
RUN mix compile
RUN mix release

FROM debian:bullseye-slim

RUN apt-get update -y && \
    apt-get install -y libstdc++6 openssl libncurses5 locales ca-certificates \
    && apt-get clean && rm -f /var/lib/apt/lists/*_*

RUN sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && locale-gen

ENV LANG=en_US.UTF-8 LANGUAGE=en_US:en LC_ALL=en_US.UTF-8

WORKDIR /app

COPY --from=builder /app/_build/prod/rel/spitegear ./

EXPOSE 4001

CMD ["/bin/sh", "-c", "/app/bin/spitegear eval 'Spitegear.Release.migrate()' && /app/bin/spitegear start"]
