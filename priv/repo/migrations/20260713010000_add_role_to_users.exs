defmodule AndnativeAi.Repo.Migrations.AddRoleToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :role, :string, null: false, default: "admin"
    end

    create constraint(:users, :users_role_must_be_known, check: "role IN ('admin', 'superadmin')")
  end
end
