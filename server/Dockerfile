FROM elixir:1.17

# Production by default. This container is what sits behind the public
# tunnel, and it used to run `mix phx.server` with no MIX_ENV — that is, in
# :dev: stack traces served to anyone who could trigger a 500, `check_origin`
# disabled, the code reloader running, and the `secret_key_base` literal from
# dev.exs, which lives in a public repo. Overridable for local work with
# `docker compose run -e MIX_ENV=dev`.
ENV MIX_ENV=prod

WORKDIR /app

# Install hex and rebar
RUN mix local.hex --force && mix local.rebar --force

# Copy deps definition first (for layer caching)
COPY mix.exs mix.lock ./

# Get dependencies
RUN mix deps.get --only $MIX_ENV && mix deps.compile

# Copy app code
COPY . .

# Compile the app
RUN mix compile

EXPOSE 4000

CMD ["mix", "phx.server"]
