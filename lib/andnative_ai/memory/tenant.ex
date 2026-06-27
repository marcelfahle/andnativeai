defmodule AndnativeAi.Memory.Tenant do
  use Ecto.Schema

  import Ecto.Changeset

  schema "tenants" do
    field :name, :string
    field :slug, :string
    field :status, :string, default: "active"

    has_many :agents, AndnativeAi.Memory.Agent
    has_many :sources, AndnativeAi.Memory.Source
    has_many :items, AndnativeAi.Memory.Item

    timestamps(type: :utc_datetime)
  end

  def changeset(tenant, attrs) do
    tenant
    |> cast(attrs, [:name, :slug, :status])
    |> validate_required([:name, :slug, :status])
    |> validate_format(:slug, ~r/^[a-z0-9][a-z0-9-]*$/)
    |> unique_constraint(:slug)
  end
end
