defmodule AndnativeAi.Slack.OAuthConfig do
  use Ecto.Schema

  import Ecto.Changeset

  schema "slack_oauth_configs" do
    field :client_id, :string
    field :client_secret, AndnativeAi.Encrypted.Binary, redact: true
    field :redirect_uri, :string
    field :bot_scopes, :string

    belongs_to :tenant, AndnativeAi.Memory.Tenant

    timestamps(type: :utc_datetime)
  end

  def changeset(config, attrs) do
    config
    |> cast(attrs, [:tenant_id, :client_id, :client_secret, :redirect_uri, :bot_scopes])
    |> validate_required([:tenant_id, :client_id, :client_secret, :bot_scopes])
    |> validate_format(:redirect_uri, ~r/^https?:\/\//)
    |> assoc_constraint(:tenant)
    |> unique_constraint(:tenant_id)
  end
end
