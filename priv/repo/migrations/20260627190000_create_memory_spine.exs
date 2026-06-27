defmodule AndnativeAi.Repo.Migrations.CreateMemorySpine do
  use Ecto.Migration

  def change do
    create table(:tenants) do
      add :name, :string, null: false
      add :slug, :string, null: false
      add :status, :string, null: false, default: "active"

      timestamps(type: :utc_datetime)
    end

    create unique_index(:tenants, [:slug])

    create table(:agents) do
      add :tenant_id, references(:tenants, on_delete: :delete_all), null: false
      add :runtime, :string, null: false, default: "openclaw"
      add :name, :string, null: false
      add :identity, :text, null: false
      add :model, :string, null: false
      add :status, :string, null: false, default: "draft"
      add :runtime_ref, :string

      timestamps(type: :utc_datetime)
    end

    create index(:agents, [:tenant_id])
    create index(:agents, [:tenant_id, :runtime])

    create table(:memory_sources) do
      add :tenant_id, references(:tenants, on_delete: :delete_all), null: false
      add :source_type, :string, null: false
      add :source_id, :string, null: false
      add :name, :string, null: false
      add :permalink_or_url, :text
      add :status, :string, null: false, default: "pending"
      add :last_ingested_at, :utc_datetime
      add :deleted_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create index(:memory_sources, [:tenant_id])

    create unique_index(:memory_sources, [:tenant_id, :source_type, :source_id],
             where: "deleted_at IS NULL"
           )

    create table(:memory_items) do
      add :tenant_id, references(:tenants, on_delete: :delete_all), null: false
      add :source_id, references(:memory_sources, on_delete: :delete_all), null: false
      add :source_type, :string, null: false
      add :channel_id, :string
      add :text, :text, null: false
      add :embedding, :vector, size: 1536
      add :provenance, :map, null: false, default: %{}
      add :visibility, :string, null: false, default: "tenant"
      add :retention_class, :string, null: false, default: "default"
      add :expires_at, :utc_datetime
      add :deleted_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create index(:memory_items, [:tenant_id])
    create index(:memory_items, [:source_id])
    create index(:memory_items, [:tenant_id, :channel_id])
    create index(:memory_items, [:tenant_id, :deleted_at])
    create index(:memory_items, [:expires_at])

    create index(:memory_items, ["embedding vector_cosine_ops"],
             using: :hnsw,
             where: "deleted_at IS NULL"
           )
  end
end
