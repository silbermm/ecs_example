FROM elixir:1.10.0-alpine AS build

ARG MIX_ENV

RUN apk add --no-cache build-base git npm python

WORKDIR /app

# install hex + rebar
RUN mix local.hex --force && \
    mix local.rebar --force

ENV MIX_ENV=${MIX_ENV}
ENV SECRET_KEY_BASE=${SECRET_KEY_BASE}

COPY mix.exs mix.lock ./
COPY config config
RUN mix do deps.get, deps.compile

COPY assets/package.json assets/package-lock.json ./assets/
RUN npm --prefix ./assets ci --progress=false --no-audit --loglevel=error

COPY priv priv
COPY assets assets
RUN npm run --prefix ./assets deploy
RUN mix phx.digest

COPY lib lib

RUN mix do compile, release

FROM alpine:3.9 AS app

ARG MIX_ENV

RUN apk add --no-cache openssl ncurses-libs

WORKDIR /app

RUN chown nobody:nobody /app

USER nobody:nobody

COPY --from=build --chown=nobody:nobody /app/_build/${MIX_ENV}/rel/ecs_app ./

ENV HOME=/app

CMD ["bin/ecs_app", "start"]
