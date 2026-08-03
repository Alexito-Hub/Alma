defmodule AlmaWeb.Router do
  use Phoenix.Router

  import Plug.Conn
  import Phoenix.Controller

  pipeline :api do
    plug :accepts, ["json"]
  end

  pipeline :authed do
    plug AlmaWeb.Plugs.Auth
  end

  # Public health probe — unauthenticated on purpose so uptime monitors (and a
  # plain browser) can reach it. Data-volume details live behind auth below.
  scope "/", AlmaWeb do
    pipe_through :api

    get "/health", HealthController, :show
  end

  scope "/api", AlmaWeb do
    pipe_through :api

    post "/auth/register", AuthController, :register
    post "/auth/login", AuthController, :login
  end

  scope "/api", AlmaWeb do
    pipe_through [:api, :authed]

    # Same report as /health plus database stats and collection counts.
    get "/health", HealthController, :detailed

    get "/auth/me", AuthController, :me
    put "/auth/avatar", AuthController, :update_avatar
    put "/auth/profile", AuthController, :update_profile
    post "/couple/link", CoupleController, :link

    # Couple invitation flow (preferred over /couple/link)
    get "/couple/requests", CoupleRequestController, :index
    post "/couple/requests", CoupleRequestController, :create
    post "/couple/requests/:id/accept", CoupleRequestController, :accept
    post "/couple/requests/:id/reject", CoupleRequestController, :reject
    post "/couple/requests/:id/cancel", CoupleRequestController, :cancel

    # Per-couple visual settings (background, tint).
    get "/couple/settings", CoupleSettingsController, :show
    put "/couple/settings", CoupleSettingsController, :update

    # Couple-shared PIN gating the private feed.
    get "/couple/pin", CoupleSettingsController, :pin_status
    put "/couple/pin", CoupleSettingsController, :set_pin
    post "/couple/pin/verify", CoupleSettingsController, :verify_pin

    post "/sync/batch", SyncController, :batch

    resources "/posts", PostController, only: [:create, :index, :show, :update, :delete]
    post "/posts/:id/comments", CommentController, :create
    get "/posts/:id/comments", CommentController, :index

    resources "/notes", NoteController, only: [:create, :index, :update, :delete]
    get "/notes/:id/comments", NoteCommentController, :index
    post "/notes/:id/comments", NoteCommentController, :create
    resources "/special_dates", SpecialDateController, only: [:index, :create, :delete]

    # "Citas": shared plans, pending and lived.
    resources "/date_ideas", DateIdeaController, only: [:index, :create, :update, :delete]

    put "/status", StatusController, :update
    get "/status", StatusController, :show

    post "/media", MediaController, :upload
  end
end
