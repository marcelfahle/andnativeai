defmodule AndnativeAi.Repo.Migrations.EncryptSlackSecrets do
  use Ecto.Migration

  import Ecto.Query

  # Encrypts slack_installations.bot_token and
  # slack_oauth_configs.client_secret at rest (DEC-011 caveat, AAI-21).
  # Plaintext text columns become Cloak AES-256-GCM bytea ciphertext;
  # existing rows are re-encrypted in place during the migration.
  def up do
    alter table(:slack_installations) do
      add :bot_token_ciphertext, :binary
    end

    alter table(:slack_oauth_configs) do
      add :client_secret_ciphertext, :binary
    end

    flush()
    vault = start_vault()

    for %{id: id, plain: plain} <-
          repo().all(from(i in "slack_installations", select: %{id: i.id, plain: i.bot_token})),
        is_binary(plain) do
      repo().update_all(from(i in "slack_installations", where: i.id == ^id),
        set: [bot_token_ciphertext: AndnativeAi.Vault.encrypt!(plain)]
      )
    end

    for %{id: id, plain: plain} <-
          repo().all(
            from(c in "slack_oauth_configs", select: %{id: c.id, plain: c.client_secret})
          ),
        is_binary(plain) do
      repo().update_all(from(c in "slack_oauth_configs", where: c.id == ^id),
        set: [client_secret_ciphertext: AndnativeAi.Vault.encrypt!(plain)]
      )
    end

    stop_vault(vault)

    alter table(:slack_installations) do
      remove :bot_token
    end

    alter table(:slack_oauth_configs) do
      remove :client_secret
    end

    rename table(:slack_installations), :bot_token_ciphertext, to: :bot_token
    rename table(:slack_oauth_configs), :client_secret_ciphertext, to: :client_secret

    # NOT NULL is restored after the data moves; new rows always encrypt.
    execute "ALTER TABLE slack_installations ALTER COLUMN bot_token SET NOT NULL"
    execute "ALTER TABLE slack_oauth_configs ALTER COLUMN client_secret SET NOT NULL"
  end

  def down do
    vault = start_vault()

    alter table(:slack_installations) do
      add :bot_token_plain, :text
    end

    alter table(:slack_oauth_configs) do
      add :client_secret_plain, :text
    end

    flush()

    for %{id: id, cipher: cipher} <-
          repo().all(from(i in "slack_installations", select: %{id: i.id, cipher: i.bot_token})),
        is_binary(cipher) do
      repo().update_all(from(i in "slack_installations", where: i.id == ^id),
        set: [bot_token_plain: AndnativeAi.Vault.decrypt!(cipher)]
      )
    end

    for %{id: id, cipher: cipher} <-
          repo().all(
            from(c in "slack_oauth_configs", select: %{id: c.id, cipher: c.client_secret})
          ),
        is_binary(cipher) do
      repo().update_all(from(c in "slack_oauth_configs", where: c.id == ^id),
        set: [client_secret_plain: AndnativeAi.Vault.decrypt!(cipher)]
      )
    end

    stop_vault(vault)

    alter table(:slack_installations) do
      remove :bot_token
    end

    alter table(:slack_oauth_configs) do
      remove :client_secret
    end

    rename table(:slack_installations), :bot_token_plain, to: :bot_token
    rename table(:slack_oauth_configs), :client_secret_plain, to: :client_secret

    execute "ALTER TABLE slack_installations ALTER COLUMN bot_token SET NOT NULL"
    execute "ALTER TABLE slack_oauth_configs ALTER COLUMN client_secret SET NOT NULL"
  end

  # The migration may run before the app supervision tree exists (release
  # boot) or inside a running node (mix). Start the vault only if absent,
  # and stop it again so the app's own vault can start cleanly afterwards.
  defp start_vault do
    case AndnativeAi.Vault.start_link([]) do
      {:ok, pid} -> pid
      {:error, {:already_started, _pid}} -> nil
    end
  end

  defp stop_vault(nil), do: :ok
  defp stop_vault(pid), do: GenServer.stop(pid)
end
