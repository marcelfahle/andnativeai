defmodule AndnativeAi.Repo.Migrations.CreateRuntimeAuditEvents do
  use Ecto.Migration

  def change do
    create table(:runtime_audit_events) do
      add :tenant_id, references(:tenants, on_delete: :delete_all), null: false
      add :agent_id, references(:agents, on_delete: :nilify_all)
      add :source_id, references(:memory_sources, on_delete: :nilify_all)
      add :memory_item_id, references(:memory_items, on_delete: :nilify_all)
      add :request_id, :string
      add :event_kind, :string, null: false
      add :component, :string, null: false
      add :actor, :string, null: false
      add :status, :string, null: false, default: "ok"
      add :summary, :text, null: false
      add :metadata, :map, null: false, default: %{}
      add :citation_url, :text
      add :occurred_at, :utc_datetime, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:runtime_audit_events, [:tenant_id, :occurred_at, :id])
    create index(:runtime_audit_events, [:agent_id])
    create index(:runtime_audit_events, [:source_id])
  end
end
