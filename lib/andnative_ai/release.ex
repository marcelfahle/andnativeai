defmodule AndnativeAi.Release do
  @moduledoc """
  Release-safe database tasks.

  These functions are called from the assembled OTP release, where Mix is not
  available. Keep seed behavior in `priv/repo/seeds.exs` so local and release
  startup use the same provisioning code.
  """

  @app :andnative_ai

  def create do
    load_app()

    for repo <- repos() do
      create_repo(repo)
    end
  end

  def migrate do
    load_app()

    for repo <- repos() do
      {:ok, _migrations, _apps} =
        Ecto.Migrator.with_repo(repo, fn repo ->
          Ecto.Migrator.run(repo, :up, all: true)
        end)
    end
  end

  def seed do
    load_app()

    seed_path = Application.app_dir(@app, "priv/repo/seeds.exs")

    for repo <- repos() do
      {:ok, _seed_result, _apps} =
        Ecto.Migrator.with_repo(repo, fn _repo ->
          Code.eval_file(seed_path)
        end)
    end
  end

  defp create_repo(repo) do
    case repo.__adapter__().storage_up(repo.config()) do
      :ok ->
        IO.puts("Created database for #{inspect(repo)}.")

      {:error, :already_up} ->
        IO.puts("Database for #{inspect(repo)} already exists.")

      {:error, term} ->
        raise "Could not create database for #{inspect(repo)}: #{inspect(term)}"
    end
  end

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  defp load_app do
    Application.load(@app)
  end
end
