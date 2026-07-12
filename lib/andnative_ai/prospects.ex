defmodule AndnativeAi.Prospects do
  @moduledoc """
  Prospect evaluation plans: one painful workflow captured during discovery,
  turned into a demo-ready evaluation plan and 90-day roadmap.
  """

  import Ecto.Query

  alias AndnativeAi.Prospects.ProspectPlan
  alias AndnativeAi.Repo

  def list_plans(tenant_id) do
    Repo.all(
      from plan in ProspectPlan,
        where: plan.tenant_id == ^tenant_id,
        order_by: [desc: plan.inserted_at]
    )
  end

  def get_plan!(tenant_id, id) do
    Repo.get_by!(ProspectPlan, id: id, tenant_id: tenant_id)
  end

  def create_plan(tenant_id, attrs) do
    %ProspectPlan{tenant_id: tenant_id}
    |> ProspectPlan.changeset(attrs)
    |> Repo.insert()
  end

  def update_plan(%ProspectPlan{} = plan, attrs) do
    plan
    |> ProspectPlan.changeset(attrs)
    |> Repo.update()
  end

  def delete_plan(%ProspectPlan{} = plan), do: Repo.delete(plan)

  def change_plan(%ProspectPlan{} = plan, attrs \\ %{}) do
    ProspectPlan.changeset(plan, attrs)
  end
end
