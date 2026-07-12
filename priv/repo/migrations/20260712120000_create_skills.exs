defmodule AndnativeAi.Repo.Migrations.CreateSkills do
  use Ecto.Migration

  def change do
    create table(:skills) do
      add :tenant_id, references(:tenants, on_delete: :delete_all), null: false
      add :name, :string, null: false
      add :description, :string, null: false, size: 1024
      add :body, :text, null: false
      add :references, :map, null: false, default: %{}
      add :version, :string, null: false
      add :license, :string
      add :compatibility, :string
      add :source_url, :string

      timestamps(type: :utc_datetime)
    end

    create unique_index(:skills, [:tenant_id, :name])

    create table(:agent_skills) do
      add :agent_id, references(:agents, on_delete: :delete_all), null: false
      add :skill_id, references(:skills, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:agent_skills, [:agent_id, :skill_id])
  end
end
