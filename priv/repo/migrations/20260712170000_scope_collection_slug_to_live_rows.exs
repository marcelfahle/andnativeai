defmodule AndnativeAi.Repo.Migrations.ScopeCollectionSlugToLiveRows do
  use Ecto.Migration

  # Collections are soft-deleted, but the slug index covered deleted rows
  # too — recreating a collection under a previous name failed silently.
  def change do
    drop unique_index(:collections, [:tenant_id, :slug])

    create unique_index(:collections, [:tenant_id, :slug],
             where: "deleted_at IS NULL",
             name: :collections_tenant_id_slug_live_index
           )
  end
end
