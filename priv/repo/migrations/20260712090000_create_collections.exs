defmodule AndnativeAi.Repo.Migrations.CreateCollections do
  use Ecto.Migration

  def change do
    create table(:collections) do
      add :tenant_id, references(:tenants, on_delete: :delete_all), null: false
      add :name, :string, null: false
      add :slug, :string, null: false
      add :kind, :string, null: false, default: "custom"
      add :description, :text, null: false
      add :deleted_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:collections, [:tenant_id, :slug])
    create index(:collections, [:tenant_id])

    alter table(:memory_sources) do
      add :collection_id, references(:collections, on_delete: :nilify_all)
    end

    create index(:memory_sources, [:collection_id])
  end
end
