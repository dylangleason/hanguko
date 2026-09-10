defmodule Hanguko.Repo do
  use Ecto.Repo,
    otp_app: :hanguko,
    adapter: Ecto.Adapters.Postgres
end
