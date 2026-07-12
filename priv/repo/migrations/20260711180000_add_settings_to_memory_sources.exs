defmodule AndnativeAi.Repo.Migrations.AddSettingsToMemorySources do
  use Ecto.Migration

  def change do
    alter table(:memory_sources) do
      add :settings, :map, null: false, default: %{}
    end
  end
end
