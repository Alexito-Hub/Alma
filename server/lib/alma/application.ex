defmodule Alma.Application do
  @moduledoc false
  use Application

  @impl true
  def start(_type, _args) do
    children =
      [
        {Phoenix.PubSub, name: Alma.PubSub},
        Alma.Media.Storage.child_spec(),
        # Owns the ETS table behind the PIN attempt limiter. Must start before
        # anything can serve a request.
        Alma.Throttle
      ] ++
        data_services() ++
        [AlmaWeb.Endpoint]

    opts = [strategy: :one_for_one, name: Alma.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Everything that needs a live database. Skipped under `:test`, where there
  # is no Mongo to talk to — without this the suite could only ever be "start
  # a database first", which is why there wasn't one.
  defp data_services do
    if Application.get_env(:alma, :start_data_services, true) do
      mongo_cfg = Application.get_env(:alma, :mongo, [])

      [
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
        # One-shot: make sure Mongo has the indexes our hot queries need.
        {Task, &Alma.MongoIndexes.ensure/0},
        # Clears media nothing references any more (see the module docs).
        Alma.MediaJanitor
      ]
    else
      []
    end
  end

  @impl true
  def config_change(changed, _new, removed) do
    AlmaWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
