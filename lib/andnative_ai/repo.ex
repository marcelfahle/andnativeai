defmodule AndnativeAi.Repo do
  use Ecto.Repo,
    otp_app: :andnative_ai,
    adapter: Ecto.Adapters.Postgres
end
