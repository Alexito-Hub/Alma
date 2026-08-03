import Config

# Alma is a JSON API: no asset pipeline, no digested static files. The
# `cache_static_manifest` this used to carry pointed at a file `mix phx.digest`
# never produces here, so every boot went looking for a manifest that could
# not exist.
config :logger, level: :info
