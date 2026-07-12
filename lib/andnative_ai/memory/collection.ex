defmodule AndnativeAi.Memory.Collection do
  use Ecto.Schema

  import Ecto.Changeset

  @kinds ~w(handbook policies product meeting_notes research conversation custom)

  schema "collections" do
    field :name, :string
    field :slug, :string
    field :kind, :string, default: "custom"
    field :description, :string
    field :deleted_at, :utc_datetime

    belongs_to :tenant, AndnativeAi.Memory.Tenant
    has_many :sources, AndnativeAi.Memory.Source, foreign_key: :collection_id

    timestamps(type: :utc_datetime)
  end

  def kinds, do: @kinds

  def changeset(collection, attrs) do
    collection
    |> cast(attrs, [:name, :kind, :description, :deleted_at])
    |> validate_required([:tenant_id, :name, :kind, :description])
    |> validate_length(:name, max: 120)
    |> validate_length(:description, min: 10, max: 500)
    |> validate_inclusion(:kind, @kinds)
    |> put_slug()
    # error_key :name so the conflict shows up on the field the admin
    # actually edits — the form has no slug input.
    |> unique_constraint([:tenant_id, :slug],
      name: :collections_tenant_id_slug_live_index,
      error_key: :name,
      message: "is already used by another collection"
    )
  end

  defp put_slug(changeset) do
    case get_field(changeset, :name) do
      nil ->
        changeset

      name ->
        slug =
          name
          |> String.downcase()
          |> String.replace(~r/[^a-z0-9]+/u, "-")
          |> String.trim("-")

        put_change(changeset, :slug, slug)
    end
  end

  @doc "Context line prepended to chunks so retrieval knows what a chunk is."
  def context_prefix(%__MODULE__{} = collection, source_name) do
    "[#{collection.name} · #{source_name}] "
  end

  def context_prefix(nil, _source_name), do: ""
end
