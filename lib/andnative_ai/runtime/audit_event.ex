defmodule AndnativeAi.Runtime.AuditEvent do
  use Ecto.Schema

  import Ecto.Changeset

  alias AndnativeAi.Runtime.AuditEventKinds

  schema "runtime_audit_events" do
    field :request_id, :string
    field :event_kind, :string
    field :component, :string
    field :actor, :string
    field :status, :string, default: "ok"
    field :summary, :string
    field :metadata, :map, default: %{}
    field :citation_url, :string
    field :occurred_at, :utc_datetime

    belongs_to :tenant, AndnativeAi.Memory.Tenant
    belongs_to :agent, AndnativeAi.Memory.Agent
    belongs_to :source, AndnativeAi.Memory.Source
    belongs_to :memory_item, AndnativeAi.Memory.Item

    timestamps(type: :utc_datetime)
  end

  def event_kinds, do: AuditEventKinds.keys()

  def changeset(event, attrs) do
    event
    |> cast(attrs, [
      :agent_id,
      :source_id,
      :memory_item_id,
      :request_id,
      :event_kind,
      :component,
      :actor,
      :status,
      :summary,
      :metadata,
      :citation_url,
      :occurred_at
    ])
    |> put_default_occurred_at()
    |> validate_required([
      :tenant_id,
      :event_kind,
      :component,
      :actor,
      :status,
      :summary,
      :metadata,
      :occurred_at
    ])
    |> validate_inclusion(:event_kind, event_kinds())
    |> validate_length(:summary, max: 500)
    |> assoc_constraint(:tenant)
    |> assoc_constraint(:agent)
    |> assoc_constraint(:source)
    |> assoc_constraint(:memory_item)
  end

  defp put_default_occurred_at(changeset) do
    case get_field(changeset, :occurred_at) do
      nil -> put_change(changeset, :occurred_at, utc_now())
      _occurred_at -> changeset
    end
  end

  defp utc_now do
    DateTime.utc_now() |> DateTime.truncate(:second)
  end
end
