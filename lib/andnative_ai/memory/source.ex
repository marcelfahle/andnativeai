defmodule AndnativeAi.Memory.Source do
  use Ecto.Schema

  import Ecto.Changeset

  schema "memory_sources" do
    field :source_type, :string
    field :source_id, :string
    field :name, :string
    field :permalink_or_url, :string
    field :status, :string, default: "pending"
    field :settings, :map, default: %{}
    field :last_ingested_at, :utc_datetime
    field :deleted_at, :utc_datetime

    belongs_to :tenant, AndnativeAi.Memory.Tenant
    belongs_to :collection, AndnativeAi.Memory.Collection
    has_many :items, AndnativeAi.Memory.Item, foreign_key: :source_id

    timestamps(type: :utc_datetime)
  end

  def changeset(source, attrs) do
    source
    |> cast(attrs, [
      :source_type,
      :source_id,
      :name,
      :permalink_or_url,
      :status,
      :settings,
      :collection_id,
      :last_ingested_at,
      :deleted_at
    ])
    |> validate_required([:tenant_id, :source_type, :source_id, :name, :status])
    |> validate_inclusion(:source_type, ["document", "slack_channel", "slack_thread"])
    |> unique_constraint([:tenant_id, :source_type, :source_id])
  end

  @doc """
  Whether app/bot-authored Slack messages (Linear updates and similar) may be
  ingested from this source. Off unless explicitly enabled per channel.
  """
  def ingest_bot_messages?(%__MODULE__{settings: %{"ingest_bot_messages" => true}}), do: true
  def ingest_bot_messages?(_source), do: false
end
