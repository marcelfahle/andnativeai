defmodule AndnativeAi.Repo.Migrations.CreateProspectPlans do
  use Ecto.Migration

  def change do
    create table(:prospect_plans) do
      add :tenant_id, references(:tenants, on_delete: :delete_all), null: false
      add :company_name, :string, null: false
      add :sector, :string
      add :workflow_pain, :text, null: false
      add :systems, :string
      add :manual_steps, :text
      add :risk_notes, :text
      add :success_metric, :string

      timestamps(type: :utc_datetime)
    end

    create index(:prospect_plans, [:tenant_id])
  end
end
