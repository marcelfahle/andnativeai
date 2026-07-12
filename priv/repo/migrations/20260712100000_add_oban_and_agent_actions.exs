defmodule AndnativeAi.Repo.Migrations.AddObanAndAgentActions do
  use Ecto.Migration

  def up do
    Oban.Migration.up(version: 14)

    create table(:agent_actions) do
      add :tenant_id, references(:tenants, on_delete: :delete_all), null: false
      add :agent_id, references(:agents, on_delete: :nilify_all)
      add :kind, :string, null: false
      add :status, :string, null: false, default: "queued"
      add :input_summary, :string, null: false
      add :input, :map, null: false, default: %{}
      add :result_path, :string
      add :result_preview, :text
      add :error, :string
      add :provider, :string
      add :cost_cents, :integer
      add :request_id, :string
      add :slack_channel_id, :string
      add :slack_thread_ts, :string
      add :approved_by, :string
      add :approved_at, :utc_datetime
      add :completed_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create index(:agent_actions, [:tenant_id, :status])
    create index(:agent_actions, [:tenant_id, :inserted_at])
  end

  def down do
    drop table(:agent_actions)
    Oban.Migration.down(version: 1)
  end
end
