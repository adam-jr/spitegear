FROM hexpm/elixir:1.18.4-erlang-28.0.2-debian-bullseye-20260421-slim

RUN apt-get update -y && apt-get install -y build-essential git \
    && apt-get clean && rm -f /var/lib/apt/lists/*_*

WORKDIR /app

RUN mix local.hex --force && mix local.rebar --force

ENV MIX_ENV=dev

COPY mix.exs mix.lock ./
RUN mix deps.get

COPY config config
COPY priv priv
COPY lib lib
COPY assets assets

RUN mix assets.build
RUN mix compile

EXPOSE 4001

CMD ["sh", "-c", "mix ecto.migrate && mix phx.server"]
