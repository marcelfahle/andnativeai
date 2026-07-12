defmodule AndnativeAi.Repo.Migrations.AddRoleAndModelPolicyToAgents do
  use Ecto.Migration

  def change do
    alter table(:agents) do
      # Customer-facing abstraction: agents are roles, not models.
      add :role, :string, null: false, default: "general"
      # Superadmin-managed: per-capability model overrides.
      add :model_policy, :map, null: false, default: %{}
    end

    create constraint(:agents, :agents_role_must_be_known,
             check: "role IN ('general', 'marketing', 'ops', 'research')"
           )

    # Model is a platform decision now; agents without one resolve to the
    # appliance default via ModelPolicy.
    execute "ALTER TABLE agents ALTER COLUMN model DROP NOT NULL",
            "ALTER TABLE agents ALTER COLUMN model SET NOT NULL"
  end
end
