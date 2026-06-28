defmodule AndnativeAi.Repo.Migrations.CreateSlackInstallations do
  use Ecto.Migration

  def change do
    create table(:slack_installations) do
      add :tenant_id, references(:tenants, on_delete: :delete_all), null: false
      add :team_id, :string, null: false
      add :team_name, :string, null: false
      add :enterprise_id, :string
      add :app_id, :string
      add :bot_user_id, :string, null: false
      add :bot_token, :text, null: false
      add :bot_scopes, :text
      add :installed_by_user_id, :string
      add :status, :string, null: false, default: "active"
      add :installed_at, :utc_datetime, null: false
      add :deleted_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create index(:slack_installations, [:tenant_id])

    create unique_index(:slack_installations, [:tenant_id, :team_id], where: "deleted_at IS NULL")

    create unique_index(:slack_installations, [:team_id], where: "deleted_at IS NULL")
  end
end
