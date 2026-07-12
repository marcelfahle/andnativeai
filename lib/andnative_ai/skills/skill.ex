defmodule AndnativeAi.Skills.Skill do
  use Ecto.Schema

  import Ecto.Changeset

  schema "skills" do
    field :name, :string
    field :description, :string
    field :body, :string
    field :references, :map, default: %{}
    field :version, :string
    field :license, :string
    field :compatibility, :string
    field :source_url, :string

    belongs_to :tenant, AndnativeAi.Memory.Tenant

    many_to_many :agents, AndnativeAi.Memory.Agent,
      join_through: "agent_skills",
      on_replace: :delete

    timestamps(type: :utc_datetime)
  end

  def changeset(skill, attrs) do
    skill
    |> cast(attrs, [
      :name,
      :description,
      :body,
      :references,
      :version,
      :license,
      :compatibility,
      :source_url
    ])
    |> validate_required([:tenant_id, :name, :description, :body, :version])
    |> validate_length(:name, max: 64)
    |> validate_format(:name, ~r/^[a-z0-9]+(-[a-z0-9]+)*$/,
      message: "must be lowercase alphanumeric with single hyphens"
    )
    |> validate_length(:description, min: 1, max: 1024)
    |> unique_constraint([:tenant_id, :name])
  end
end
