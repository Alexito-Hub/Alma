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

  scope "/api", AlmaWeb do
    pipe_through :api

    post "/auth/register", AuthController, :register
    post "/auth/login", AuthController, :login
  end

  scope "/api", AlmaWeb do
    pipe_through [:api, :authed]

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

    post "/sync/batch", SyncController, :batch

    resources "/posts", PostController, only: [:create, :index, :show]
    post "/posts/:id/comments", CommentController, :create
    get "/posts/:id/comments", CommentController, :index

    resources "/notes", NoteController, only: [:create, :index]
    resources "/special_dates", SpecialDateController, only: [:index, :create, :delete]
    put "/status", StatusController, :update
    get "/status", StatusController, :show

    post "/media", MediaController, :upload
  end
end
