defmodule AndnativeAi.Memory.Agent do
  use Ecto.Schema

  import Ecto.Changeset

  # Customer-facing roles — agents are roles, not models. Model choice
  # lives in model_policy and is a platform (superadmin) decision.
  @roles ~w(general marketing ops research)

  schema "agents" do
    field :runtime, :string, default: "openclaw"
    field :name, :string
    field :identity, :string
    field :role, :string, default: "general"
    field :model, :string
    field :model_policy, :map, default: %{}
    field :status, :string, default: "draft"
    field :runtime_ref, :string

    belongs_to :tenant, AndnativeAi.Memory.Tenant

    timestamps(type: :utc_datetime)
  end

  def roles, do: @roles

  @doc """
  Customer-facing changeset: name, identity, role, status. Deliberately
  does NOT cast :model or :model_policy — those change only through
  `model_policy_changeset/2` (superadmin, audited).
  """
  def changeset(agent, attrs) do
    agent
    |> cast(attrs, [:runtime, :name, :identity, :role, :status, :runtime_ref])
    |> validate_required([:tenant_id, :runtime, :name, :identity, :role, :status])
    |> validate_inclusion(:runtime, ["openclaw"])
    |> validate_inclusion(:role, @roles)
    |> check_constraint(:role, name: :agents_role_must_be_known)
  end

  @doc "Superadmin-only changeset for the base model and per-capability overrides."
  def model_policy_changeset(agent, attrs) do
    agent
    |> cast(attrs, [:model, :model_policy])
    |> update_change(:model_policy, &drop_blank_overrides/1)
    |> validate_change(:model_policy, &validate_policy_capabilities/2)
  end

  defp drop_blank_overrides(policy) when is_map(policy) do
    policy
    |> Enum.reject(fn {_capability, model} -> model in [nil, ""] end)
    |> Map.new()
  end

  defp drop_blank_overrides(other), do: other

  defp validate_policy_capabilities(:model_policy, policy) when is_map(policy) do
    known = AndnativeAi.Runtime.ModelPolicy.capabilities()

    case Enum.reject(Map.keys(policy), &(&1 in known)) do
      [] -> []
      unknown -> [model_policy: "unknown capabilities: #{Enum.join(unknown, ", ")}"]
    end
  end

  defp validate_policy_capabilities(:model_policy, _other),
    do: [model_policy: "must be a map of capability to model"]
end
