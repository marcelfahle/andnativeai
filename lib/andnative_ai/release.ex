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

  @doc """
  Hard-deletes all memory sources and items for the demo tenant while keeping
  agents and config. Release-safe equivalent of
  `mix run scripts/reset-demo-memory.exs`, meant for resetting the live demo
  appliance between recordings.
  """
  def reset_demo_memory do
    import Ecto.Query

    with_task_env(fn repo ->
      tenant = AndnativeAi.Memory.ensure_demo_tenant!()

      {item_count, _} =
        repo.delete_all(
          from(item in AndnativeAi.Memory.Item, where: item.tenant_id == ^tenant.id)
        )

      {source_count, _} =
        repo.delete_all(
          from(source in AndnativeAi.Memory.Source, where: source.tenant_id == ^tenant.id)
        )

      IO.puts(
        "Deleted #{item_count} memory items and #{source_count} sources for #{tenant.slug}."
      )
    end)
  end

  @doc """
  Replaces and backfills one public Slack channel for the demo tenant.
  Release-safe equivalent of `mix run scripts/backfill-slack-channel.exs`.

  Bot credentials come from the latest OAuth installation, with the
  `SLACK_BOT_TOKEN`/`SLACK_BOT_USER_ID` env fallback for manual setups.
  """
  def backfill_slack_channel(channel_id) when is_binary(channel_id) do
    {:ok, _apps} = Application.ensure_all_started(:req)

    with_task_env(fn _repo ->
      tenant = AndnativeAi.Memory.ensure_demo_tenant!()

      case slack_credentials(tenant.id) do
        {:ok, bot_token, bot_user_id} ->
          history_limit = System.get_env("SLACK_HISTORY_LIMIT", "50") |> String.to_integer()

          AndnativeAi.Slack.Ingestion.delete_channel(tenant.id, channel_id)

          {:ok, %{items: items, source: source}} =
            AndnativeAi.Slack.Ingestion.backfill_channel(
              tenant.id,
              %{"channel" => channel_id},
              bot_token: bot_token,
              bot_user_id: bot_user_id,
              history_limit: history_limit
            )

          IO.puts(
            "Backfilled #{length(items)} memory items for #{source.name} (#{source.source_id})."
          )

        :error ->
          IO.puts(
            "No Slack credentials found: connect Slack via OAuth in /admin/slack " <>
              "or set SLACK_BOT_TOKEN and SLACK_BOT_USER_ID."
          )
      end
    end)
  end

  @doc """
  Re-embeds all active memory items with the currently configured
  embedding provider (e.g. after setting OPENAI_API_KEY). Run via
  `just prod-eval "AndnativeAi.Release.reembed_memory()"`.
  """
  def reembed_memory do
    with_task_env(fn _repo ->
      Enum.each(AndnativeAi.Memory.list_tenants(), fn tenant ->
        count = AndnativeAi.Memory.SituateWorker.reembed_all(tenant.id)
        IO.puts("Re-embedded #{count} memory items for #{tenant.slug}.")
      end)
    end)
  end

  @doc """
  Promotes a user to platform superadmin by email. The only supported way
  to grant the role on a live appliance:
  `just prod-eval "AndnativeAi.Release.promote_superadmin(\\\"ops@andnative.ai\\\")"`.
  """
  def promote_superadmin(email) when is_binary(email) do
    with_task_env(fn _repo ->
      case AndnativeAi.Accounts.promote_to_superadmin(email) do
        {:ok, user} ->
          IO.puts("#{user.email} is now a superadmin.")

        {:error, :not_found} ->
          IO.puts("No user found with email #{email}.")

        {:error, changeset} ->
          IO.puts("Could not promote #{email}: #{inspect(changeset.errors)}")
      end
    end)
  end

  @doc """
  Rotates a platform superadmin's password out of band — the only
  supported rotation path, since superadmins are excluded from the
  public self-serve reset flow (AAI-34). Prints the new password once.
  """
  def rotate_superadmin_password(email) when is_binary(email) do
    with_task_env(fn _repo ->
      case AndnativeAi.Accounts.get_user_by_email(email) do
        %{role: "superadmin"} = user ->
          new_password = AndnativeAi.Accounts.generate_random_password()

          case AndnativeAi.Accounts.reset_user_password(user, %{password: new_password}) do
            {:ok, _user} ->
              IO.puts("New password for #{email}: #{new_password}")

            {:error, changeset} ->
              IO.puts("Could not rotate #{email}: #{inspect(changeset.errors)}")
          end

        %{} ->
          IO.puts("#{email} is not a superadmin; use the in-app reset flow.")

        nil ->
          IO.puts("No user found with email #{email}.")
      end
    end)
  end

  defp slack_credentials(tenant_id) do
    AndnativeAi.Slack.Installations.bot_credentials(tenant_id)
  end

  # Runs a task with the repo started and a PubSub instance available, so
  # audit writes (which broadcast to the control plane) work from
  # `bin/andnative_ai eval`, where the app supervision tree is not running.
  defp with_task_env(fun) do
    load_app()

    for repo <- repos() do
      {:ok, _result, _apps} =
        Ecto.Migrator.with_repo(repo, fn started_repo ->
          ensure_pubsub_started()
          ensure_vault_started()
          fun.(started_repo)
        end)
    end

    :ok
  end

  defp ensure_vault_started do
    case AndnativeAi.Vault.start_link([]) do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
    end
  end

  defp ensure_pubsub_started do
    # In `bin/andnative_ai eval` no applications are running; the PG2
    # adapter needs the :phoenix_pubsub application's registry process
    # before a PubSub instance can start.
    {:ok, _apps} = Application.ensure_all_started(:phoenix_pubsub)

    if Process.whereis(AndnativeAi.PubSub) do
      :ok
    else
      {:ok, _pid} =
        Supervisor.start_link([{Phoenix.PubSub, name: AndnativeAi.PubSub}],
          strategy: :one_for_one
        )

      :ok
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
