defmodule Alma.Application do
  @moduledoc false
  use Application

  @impl true
  def start(_type, _args) do
    mongo_cfg = Application.get_env(:alma, :mongo, [])

    children = [
      {Phoenix.PubSub, name: Alma.PubSub},
      {Mongo,
       [
         name: :mongo,
         url: mongo_cfg[:url],
         pool_size: mongo_cfg[:pool_size] || 5,
         ssl: true,
         ssl_opts: [
           verify: :verify_peer,
           cacerts: :public_key.cacerts_get(),
           customize_hostname_check: [
             match_fun: :public_key.pkix_verify_hostname_match_fun(:https)
           ]
         ]
       ]},
      Alma.Media.Storage.child_spec(),
      AlmaWeb.Endpoint
    ]

    opts = [strategy: :one_for_one, name: Alma.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @impl true
  def config_change(changed, _new, removed) do
    AlmaWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
