defmodule AndnativeAi.Memory.Agent do
  use Ecto.Schema

  import Ecto.Changeset

  schema "agents" do
    field :runtime, :string, default: "openclaw"
    field :name, :string
    field :identity, :string
    field :model, :string
    field :status, :string, default: "draft"
    field :runtime_ref, :string

    belongs_to :tenant, AndnativeAi.Memory.Tenant

    timestamps(type: :utc_datetime)
  end

  def changeset(agent, attrs) do
    agent
    |> cast(attrs, [:runtime, :name, :identity, :model, :status, :runtime_ref])
    |> validate_required([:tenant_id, :runtime, :name, :identity, :model, :status])
    |> validate_inclusion(:runtime, ["openclaw"])
  end
end
