defmodule AndnativeAi.Repo.Migrations.SeedFirstAdmin do
  use Ecto.Migration

  # Bootstraps the first admin so a fresh deploy can log in immediately.
  #
  # Default password: changeme123 — the operator logs in and changes it at
  # /users/settings on first login. This is a deliberate, resettable bootstrap
  # value, not a real secret.
  #
  # Idempotent (ON CONFLICT DO NOTHING) and skipped for the test database so it
  # never pollutes the test suite's user table.
  @email "m.fahle@gmail.com"

  def up do
    unless test_database?() or provisioned_appliance?() do
      hashed_password = Bcrypt.hash_pwd_salt("changeme123")

      repo().query!(
        """
        INSERT INTO users (email, hashed_password, confirmed_at, inserted_at, updated_at)
        VALUES (
          $1,
          $2,
          (NOW() AT TIME ZONE 'UTC'),
          (NOW() AT TIME ZONE 'UTC'),
          (NOW() AT TIME ZONE 'UTC')
        )
        ON CONFLICT (email) DO NOTHING
        """,
        [@email, hashed_password]
      )
    end
  end

  def down do
    # Only remove the bootstrap row while it still has the default password —
    # never delete an admin that has been adopted (password changed).
    case repo().query!("SELECT hashed_password FROM users WHERE email = $1", [@email]) do
      %{rows: [[hashed_password]]} ->
        if Bcrypt.verify_pass("changeme123", hashed_password) do
          repo().query!("DELETE FROM users WHERE email = $1", [@email])
        end

      _ ->
        :ok
    end
  end

  # Provisioned appliances (provision-appliance.sh) seed their own first
  # admin via SEED_ADMIN_EMAIL; the demo bootstrap account with its default
  # password must never exist on a customer box.
  defp provisioned_appliance? do
    System.get_env("SEED_ADMIN_EMAIL") not in [nil, ""]
  end

  # The test database name carries an optional MIX_TEST_PARTITION suffix
  # (e.g. andnative_ai_test, andnative_ai_test1), so match the `_test[N]` stem
  # rather than a literal suffix.
  defp test_database? do
    %{rows: [[database]]} = repo().query!("SELECT current_database()")
    Regex.match?(~r/_test\d*$/, database)
  end
end
