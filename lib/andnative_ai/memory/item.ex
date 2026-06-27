defmodule AndnativeAi.Memory.Item do
  use Ecto.Schema

  import Ecto.Changeset

  schema "memory_items" do
    field :source_type, :string
    field :channel_id, :string
    field :text, :string
    field :embedding, Pgvector.Ecto.Vector
    field :provenance, :map, default: %{}
    field :visibility, :string, default: "tenant"
    field :retention_class, :string, default: "default"
    field :expires_at, :utc_datetime
    field :deleted_at, :utc_datetime

    belongs_to :tenant, AndnativeAi.Memory.Tenant
    belongs_to :source, AndnativeAi.Memory.Source

    timestamps(type: :utc_datetime)
  end

  def changeset(item, attrs) do
    item
    |> cast(attrs, [
      :source_type,
      :channel_id,
      :text,
      :embedding,
      :provenance,
      :visibility,
      :retention_class,
      :expires_at,
      :deleted_at
    ])
    |> validate_required([
      :tenant_id,
      :source_id,
      :source_type,
      :text,
      :provenance,
      :visibility,
      :retention_class
    ])
    |> validate_inclusion(:source_type, ["document", "slack_channel", "slack_thread"])
    |> validate_inclusion(:visibility, ["tenant", "agent", "source"])
    |> assoc_constraint(:tenant)
    |> assoc_constraint(:source)
  end
end
