FROM elixir:1.17

WORKDIR /app

# Install hex and rebar
RUN mix local.hex --force && mix local.rebar --force

# Copy deps definition first (for layer caching)
COPY mix.exs mix.lock ./

# Get dependencies
RUN mix deps.get && mix deps.compile

# Copy app code
COPY . .

# Compile the app
RUN mix compile

EXPOSE 4000

CMD ["mix", "phx.server"]
