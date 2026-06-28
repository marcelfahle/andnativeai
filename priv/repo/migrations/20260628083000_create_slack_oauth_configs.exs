defmodule AndnativeAi.Repo.Migrations.CreateSlackOAuthConfigs do
  use Ecto.Migration

  def change do
    create table(:slack_oauth_configs) do
      add :tenant_id, references(:tenants, on_delete: :delete_all), null: false
      add :client_id, :string, null: false
      add :client_secret, :text, null: false
      add :redirect_uri, :text
      add :bot_scopes, :text, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:slack_oauth_configs, [:tenant_id])
  end
end
