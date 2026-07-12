defmodule AndnativeAi.Repo.Migrations.AddContextToMemoryItems do
  use Ecto.Migration

  def change do
    alter table(:memory_items) do
      add :context, :text
    end
  end
end
