defmodule AndnativeAi.Slack.Installation do
  use Ecto.Schema

  import Ecto.Changeset

  schema "slack_installations" do
    field :team_id, :string
    field :team_name, :string
    field :enterprise_id, :string
    field :app_id, :string
    field :bot_user_id, :string
    field :bot_token, :string
    field :bot_scopes, :string
    field :installed_by_user_id, :string
    field :status, :string, default: "active"
    field :installed_at, :utc_datetime
    field :deleted_at, :utc_datetime

    belongs_to :tenant, AndnativeAi.Memory.Tenant

    timestamps(type: :utc_datetime)
  end

  def changeset(installation, attrs) do
    installation
    |> cast(attrs, [
      :tenant_id,
      :team_id,
      :team_name,
      :enterprise_id,
      :app_id,
      :bot_user_id,
      :bot_token,
      :bot_scopes,
      :installed_by_user_id,
      :status,
      :installed_at,
      :deleted_at
    ])
    |> validate_required([
      :tenant_id,
      :team_id,
      :team_name,
      :bot_user_id,
      :bot_token,
      :status,
      :installed_at
    ])
    |> validate_inclusion(:status, ["active", "revoked"])
    |> assoc_constraint(:tenant)
    |> unique_constraint(:team_id)
  end
end
