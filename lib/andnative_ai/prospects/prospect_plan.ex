defmodule AndnativeAi.Prospects.ProspectPlan do
  use Ecto.Schema

  import Ecto.Changeset

  schema "prospect_plans" do
    field :company_name, :string
    field :sector, :string
    field :workflow_pain, :string
    field :systems, :string
    field :manual_steps, :string
    field :risk_notes, :string
    field :success_metric, :string

    belongs_to :tenant, AndnativeAi.Memory.Tenant

    timestamps(type: :utc_datetime)
  end

  def changeset(plan, attrs) do
    plan
    |> cast(attrs, [
      :company_name,
      :sector,
      :workflow_pain,
      :systems,
      :manual_steps,
      :risk_notes,
      :success_metric
    ])
    |> validate_required([:tenant_id, :company_name, :workflow_pain])
    |> validate_length(:company_name, max: 160)
    |> validate_length(:workflow_pain, max: 2000)
  end
end
